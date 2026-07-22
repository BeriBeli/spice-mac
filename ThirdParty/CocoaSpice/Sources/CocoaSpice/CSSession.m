//
// Copyright © 2020 osy. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "CocoaSpice.h"
#import <glib.h>
#import <spice-client.h>
#import <spice/vd_agent.h>

const NSNotificationName kCSPasteboardChangedNotification = @"CSPasteboardChangedNotification";
const NSNotificationName kCSPasteboardRemovedNotification = @"CSPasteboardRemovedNotification";

@interface CSSession ()

@property (nonatomic, readwrite, nullable) SpiceSession *session;
@property (nonatomic, readonly) BOOL sessionReadOnly;
@property (nonatomic, nullable) SpiceMainChannel *main;
/// Mutated only in the SPICE GLib context after connection setup.
@property (nonatomic) NSUInteger clipboardGeneration;
@property (nonatomic) NSUInteger guestClipboardGeneration;
/// Guest clipboard reads awaiting a main-thread pasteboard lookup. Mutated only
/// in the SPICE GLib context; one entry per supported clipboard type bounds work.
@property (nonatomic) NSMutableSet<NSString *> *clipboardRequestsInFlight;
@property (nonatomic) NSUInteger clipboardReadsOutstanding;
@property (nonatomic) guint32 hostClipboardOfferedType;
/// Snapshot of the host clipboard for the current generation. Values are NSData
/// or NSNull for a missing representation, so repeated guest requests never
/// rematerialize promised pasteboard data on AppKit's main thread.
@property (nonatomic) NSMutableDictionary<NSNumber *, id> *clipboardReadCache;

@end

@interface CSSession (Sharing)

- (void)createDefaultShareReadme;

@end

@implementation CSSession

static CSPasteboardType cspbTypeForClipboardType(guint type)
{
    switch (type) {
        case VD_AGENT_CLIPBOARD_UTF8_TEXT: {
            return kCSPasteboardTypeString;
        }
        case VD_AGENT_CLIPBOARD_IMAGE_PNG: {
            return kCSPasteboardTypePng;
        }
        case VD_AGENT_CLIPBOARD_IMAGE_BMP: {
            return kCSPasteboardTypeBmp;
        }
        case VD_AGENT_CLIPBOARD_IMAGE_TIFF: {
            return kCSPasteboardTypeTiff;
        }
        case VD_AGENT_CLIPBOARD_IMAGE_JPG: {
            return kCSPasteboardTypeJpg;
        }
        default: {
            break;
        }
    }
    return kCSPasteboardTypeString;
}

static BOOL cs_clipboard_type_is_supported(guint type)
{
    switch (type) {
        case VD_AGENT_CLIPBOARD_UTF8_TEXT:
        case VD_AGENT_CLIPBOARD_IMAGE_PNG:
        case VD_AGENT_CLIPBOARD_IMAGE_BMP:
        case VD_AGENT_CLIPBOARD_IMAGE_TIFF:
        case VD_AGENT_CLIPBOARD_IMAGE_JPG:
            return YES;
        default:
            return NO;
    }
}

// helper from spice-util.c

typedef enum {
    NEWLINE_TYPE_LF,
    NEWLINE_TYPE_CR_LF
} NewlineType;

static gssize get_line(const gchar *str, gsize len,
                       NewlineType type, gsize *nl_len)
{
    const gchar *p, *endl;
    gsize nl = 0;

    endl = (type == NEWLINE_TYPE_CR_LF) ? "\r\n" : "\n";
    p = g_strstr_len(str, len, endl);
    if (p) {
        len = p - str;
        nl = strlen(endl);
    }

    *nl_len = nl;
    return len;
}

static gchar* spice_convert_newlines(const gchar *str, gssize len,
                                     NewlineType from,
                                     NewlineType to)
{
    gssize length;
    gsize nl;
    GString *output;
    gint i;

    g_return_val_if_fail(str != NULL, NULL);
    g_return_val_if_fail(len >= -1, NULL);
    /* only 2 supported combinations */
    g_return_val_if_fail((from == NEWLINE_TYPE_LF &&
                          to == NEWLINE_TYPE_CR_LF) ||
                         (from == NEWLINE_TYPE_CR_LF &&
                          to == NEWLINE_TYPE_LF), NULL);

    if (len == -1)
        len = strlen(str);
    /* sometime we get \0 terminated strings, skip that, or it fails
       to utf8 validate line with \0 end */
    else if (len > 0 && str[len-1] == 0)
        len -= 1;

    /* allocate worst case, if it's small enough, we don't care much,
     * if it's big, malloc will put us in mmap'd region, and we can
     * over allocate.
     */
    output = g_string_sized_new(len * 2 + 1);

    for (i = 0; i < len; i += length + nl) {
        length = get_line(str + i, len - i, from, &nl);
        if (length < 0)
            break;

        g_string_append_len(output, str + i, length);

        if (nl) {
            /* let's not double \r if it's already in the line */
            if (to == NEWLINE_TYPE_CR_LF &&
                (output->len == 0 || output->str[output->len - 1] != '\r'))
                g_string_append_c(output, '\r');

            g_string_append_c(output, '\n');
        }
    }

    return g_string_free(output, FALSE);
}

G_GNUC_INTERNAL
gchar* spice_dos2unix(const gchar *str, gssize len)
{
    return spice_convert_newlines(str, len,
                                  NEWLINE_TYPE_CR_LF,
                                  NEWLINE_TYPE_LF);
}

G_GNUC_INTERNAL
gchar* spice_unix2dos(const gchar *str, gssize len)
{
    return spice_convert_newlines(str, len,
                                  NEWLINE_TYPE_LF,
                                  NEWLINE_TYPE_CR_LF);
}

static void cs_clipboard_got_from_guest(SpiceMainChannel *main, guint selection,
                                        guint type, const guchar *data, guint size,
                                        gpointer user_data)
{
    CSSession *self = (__bridge CSSession *)user_data;
    char *textData;

    SPICE_DEBUG("clipboard got data");

    if (!self.shareClipboard ||
        self.guestClipboardGeneration != self.clipboardGeneration) {
        SPICE_DEBUG("dropping stale clipboard data");
        return;
    }
    
    if (type == VD_AGENT_CLIPBOARD_UTF8_TEXT && size > 0) {
        gchar *conv = NULL;
        /* on windows, gtk+ would already convert to LF endings, but
           not on unix */
        if (spice_main_channel_agent_test_capability(self.main, VD_AGENT_CAP_GUEST_LINEEND_CRLF)) {
            conv = spice_dos2unix((gchar*)data, size);
            size = (guint)strlen(conv);
        }
        // original data may not be null terminated
        textData = calloc(size + 1, sizeof(char));
        memcpy(textData, conv ? conv : (const char *)data, size);
        NSString *string = [NSString stringWithUTF8String:textData];
        free(textData);
        [self.pasteboardDelegate setString:string];
        g_free(conv);
    } else if (type == VD_AGENT_CLIPBOARD_UTF8_TEXT) {
        [self.pasteboardDelegate setString:@""];
    } else {
        CSPasteboardType cspbType = cspbTypeForClipboardType(type);
        NSData *pasteData = [NSData dataWithBytes:data length:size];
        [self.pasteboardDelegate setData:pasteData forType:cspbType];
    }
}

static gboolean cs_clipboard_grab(SpiceMainChannel *main, guint selection,
                                  guint32* types, guint32 ntypes,
                                  gpointer user_data)
{
    CSSession *self = (__bridge CSSession *)user_data;
    
    if (selection != VD_AGENT_CLIPBOARD_SELECTION_CLIPBOARD) {
        SPICE_DEBUG("skipping grab unimplemented selection: %d", selection);
        return FALSE;
    }

    if (self.sessionReadOnly || !self.shareClipboard) {
        SPICE_DEBUG("ignoring clipboard_grab");
        return TRUE;
    }

    self.guestClipboardGeneration = self.clipboardGeneration;

    // spice-mac (fix): a guest grab is ONE new clipboard offering that may carry
    // several representations at once (e.g. a copied spreadsheet cell = UTF8 text
    // + a bitmap image). Take ownership of the host pasteboard exactly once here;
    // the per-type data that arrives next (cs_clipboard_got_from_guest) is then
    // ACCUMULATED onto it. Previously each arriving type cleared the pasteboard
    // before writing, so a multi-format guest copy lost all but the last type
    // (commonly the image), and pasting the cell's text on the Mac got nothing.
    [self.pasteboardDelegate clearContents];

    NSUInteger generation = self.clipboardGeneration;
    guint32 *requestedTypes = g_new(guint32, ntypes);
    memcpy(requestedTypes, types, sizeof(guint32) * ntypes);
    g_object_ref(main);
    [CSMain.sharedInstance asyncWith:^{
        if (self.shareClipboard && generation == self.clipboardGeneration) {
            for (int n = 0; n < ntypes; ++n) {
                spice_main_channel_clipboard_selection_request(main, selection,
                                                               requestedTypes[n]);
            }
        }
        g_free(requestedTypes);
        g_object_unref(main);
    }];

    return TRUE;
}

static gboolean cs_clipboard_request(SpiceMainChannel *main, guint selection,
                                     guint type, gpointer user_data)
{
    CSSession *self = (__bridge CSSession *)user_data;
    
    if (selection != VD_AGENT_CLIPBOARD_SELECTION_CLIPBOARD) {
        SPICE_DEBUG("skipping request unimplemented selection: %d", selection);
        return FALSE;
    }

    if (self.sessionReadOnly || !self.shareClipboard) {
        SPICE_DEBUG("ignoring clipboard_request");
        return FALSE;
    }

    if (!cs_clipboard_type_is_supported(type)) {
        SPICE_DEBUG("ignoring unsupported clipboard type: %u", type);
        return FALSE;
    }
    if (type != self.hostClipboardOfferedType) {
        SPICE_DEBUG("ignoring clipboard type that was not offered: %u", type);
        return FALSE;
    }

    NSUInteger generation = self.clipboardGeneration;
    id cachedValue = self.clipboardReadCache[@(type)];
    if (cachedValue) {
        if (cachedValue != NSNull.null) {
            NSData *cachedData = cachedValue;
            spice_main_channel_clipboard_selection_notify(main, selection, type,
                                                          cachedData.bytes, cachedData.length);
        }
        return TRUE;
    }

    NSString *requestKey = [NSString stringWithFormat:@"%p:%lu:%u",
                            main, (unsigned long)generation, type];
    if ([self.clipboardRequestsInFlight containsObject:requestKey]) {
        return TRUE;
    }
    if (self.clipboardReadsOutstanding >= 5) {
        SPICE_DEBUG("ignoring clipboard request: too many reads in flight");
        return FALSE;
    }
    [self.clipboardRequestsInFlight addObject:requestKey];
    self.clipboardReadsOutstanding += 1;

    CSPasteboardType cspbType = cspbTypeForClipboardType(type);
    g_object_ref(main);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSData *data = [self.pasteboardDelegate dataForType:cspbType];
        [CSMain.sharedInstance asyncWith:^{
            [self.clipboardRequestsInFlight removeObject:requestKey];
            if (self.clipboardReadsOutstanding > 0) {
                self.clipboardReadsOutstanding -= 1;
            }
            if (self.main == main && self.shareClipboard &&
                generation == self.clipboardGeneration) {
                self.clipboardReadCache[@(type)] = data ?: NSNull.null;
                if (data) {
                    spice_main_channel_clipboard_selection_notify(main, selection, type,
                                                                  data.bytes, data.length);
                }
            }
            g_object_unref(main);
        }];
    });

    return TRUE;
}

static void cs_clipboard_release(SpiceMainChannel *main, guint selection,
                                 gpointer user_data)
{
    CSSession *self = (__bridge CSSession *)user_data;
    if (!self.shareClipboard ||
        self.guestClipboardGeneration != self.clipboardGeneration) {
        SPICE_DEBUG("ignoring stale clipboard_release");
        return;
    }
    [self.pasteboardDelegate clearContents];
}

static void cs_channel_new(SpiceSession *session, SpiceChannel *channel,
                           gpointer user_data)
{
    CSSession *self = (__bridge CSSession *)user_data;

    if (SPICE_IS_MAIN_CHANNEL(channel)) {
        SPICE_DEBUG("Changing main channel from %p to %p", self.main, channel);
        self.main = g_object_ref(SPICE_MAIN_CHANNEL(channel));
        g_signal_connect(channel, "main-clipboard-selection-grab",
                         G_CALLBACK(cs_clipboard_grab), (__bridge void *)self);
        g_signal_connect(channel, "main-clipboard-selection-request",
                         G_CALLBACK(cs_clipboard_request), (__bridge void *)self);
        g_signal_connect(channel, "main-clipboard-selection-release",
                         G_CALLBACK(cs_clipboard_release), (__bridge void *)self);
        g_signal_connect(channel, "main-clipboard-selection",
                         G_CALLBACK(cs_clipboard_got_from_guest), (__bridge void *)self);
    }
}

static void cs_channel_destroy(SpiceSession *session, SpiceChannel *channel,
                               gpointer user_data)
{
    CSSession *self = (__bridge CSSession *)user_data;

    if (SPICE_IS_MAIN_CHANNEL(channel)) {
        g_assert(SPICE_MAIN_CHANNEL(channel) == self.main);
        NSString *requestPrefix = [NSString stringWithFormat:@"%p:", channel];
        for (NSString *requestKey in self.clipboardRequestsInFlight.copy) {
            if ([requestKey hasPrefix:requestPrefix]) {
                [self.clipboardRequestsInFlight removeObject:requestKey];
            }
        }
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_clipboard_grab), (__bridge void *)self);
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_clipboard_request), (__bridge void *)self);
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_clipboard_release), (__bridge void *)self);
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_clipboard_got_from_guest), (__bridge void *)self);
        g_object_unref(self.main);
        self.main = NULL;
    }
}

#pragma mark - Initializers

- (id)init {
    if (self = [super init]) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(pasteboardDidChange:)
                                                     name:kCSPasteboardChangedNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(pasteboardDidRemove:)
                                                     name:kCSPasteboardRemovedNotification
                                                   object:nil];
        _shareClipboard = YES;
        self.clipboardGeneration = 1;
        self.clipboardRequestsInFlight = [NSMutableSet set];
        self.clipboardReadCache = [NSMutableDictionary dictionary];
        self.hostClipboardOfferedType = VD_AGENT_CLIPBOARD_NONE;
    }
    return self;
}

- (id)initWithSession:(nonnull SpiceSession *)session {
    self = [self init];
    if (self) {
        GList *list;
        GList *it;
        
        self.session = g_object_ref(session);
        
        // spice-mac (security): do NOT auto-share a WRITABLE host directory with
        // every guest. The upstream default exposed a read-write folder to an
        // untrusted VM (a hostile guest could write/fill files on the host). Folder
        // sharing should be opt-in and read-only by default; until there's UI for
        // that, leave no directory shared.
        //   [self createDefaultShareReadme];
        //   [self setSharedDirectory:self.defaultPublicShare.path readOnly:NO];

        SPICE_DEBUG("[CocoaSpice] %s:%d", __FUNCTION__, __LINE__);
        g_signal_connect(session, "channel-new",
                         G_CALLBACK(cs_channel_new), (__bridge void *)self);
        g_signal_connect(session, "channel-destroy",
                         G_CALLBACK(cs_channel_destroy), (__bridge void *)self);
        list = spice_session_get_channels(session);
        for (it = g_list_first(list); it != NULL; it = g_list_next(it)) {
            cs_channel_new(session, it->data, (__bridge void *)self);
        }
        g_list_free(list);
    }
    return self;
}

- (void)dealloc {
    SPICE_DEBUG("[CocoaSpice] %s:%d", __FUNCTION__, __LINE__);
    SpiceSession *session = self.session;
    gpointer data = (__bridge void *)self;
    [CSMain.sharedInstance syncWith:^{
        g_signal_handlers_disconnect_by_func(session, G_CALLBACK(cs_channel_new), data);
        g_signal_handlers_disconnect_by_func(session, G_CALLBACK(cs_channel_destroy), data);
        cs_channel_destroy(session, SPICE_CHANNEL(self.main), (__bridge void *)self);
        g_object_unref(session);
    }];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:kCSPasteboardChangedNotification
                                                  object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:kCSPasteboardRemovedNotification
                                                  object:nil];
}

#pragma mark - Notification handler

- (void)pasteboardDidChange:(NSNotification *)notification {
    SPICE_DEBUG("[CocoaSpice] seen UIPasteboardChangedNotification");
    // NotificationCenter calls us on AppKit's main thread. Inspect NSPasteboard
    // here, then cross into the GLib context before reading session state.
    guint32 type = VD_AGENT_CLIPBOARD_NONE;
    id<CSPasteboardDelegate> pb = self.pasteboardDelegate;
    if ([pb canReadItemForType:kCSPasteboardTypePng]) {
        type = VD_AGENT_CLIPBOARD_IMAGE_PNG;
    } else if ([pb canReadItemForType:kCSPasteboardTypeBmp]) {
        type = VD_AGENT_CLIPBOARD_IMAGE_BMP;
    } else if ([pb canReadItemForType:kCSPasteboardTypeTiff]) {
        type = VD_AGENT_CLIPBOARD_IMAGE_TIFF;
    } else if ([pb canReadItemForType:kCSPasteboardTypeJpg]) {
        type = VD_AGENT_CLIPBOARD_IMAGE_JPG;
    } else if ([pb canReadItemForType:kCSPasteboardTypeString]) {
        type = VD_AGENT_CLIPBOARD_UTF8_TEXT;
    } else {
        SPICE_DEBUG("[CocoaSpice] pasteboard with unrecognized type");
    }
    [CSMain.sharedInstance asyncWith:^{
        self.clipboardGeneration += 1;
        [self.clipboardReadCache removeAllObjects];
        [self.clipboardRequestsInFlight removeAllObjects];
        self.hostClipboardOfferedType = type;
        if (!self.main || !self.shareClipboard || self.sessionReadOnly || !self.pasteboardDelegate) {
            return;
        }
        if (spice_main_channel_agent_test_capability(self.main, VD_AGENT_CAP_CLIPBOARD_BY_DEMAND)) {
            guint32 offeredType = type;
            spice_main_channel_clipboard_selection_grab(self.main,
                                                        VD_AGENT_CLIPBOARD_SELECTION_CLIPBOARD,
                                                        &offeredType, 1);
        }
    }];
}

- (void)pasteboardDidRemove:(NSNotification *)notification {
    SPICE_DEBUG("[CocoaSpice] seen UIPasteboardRemovedNotification");
    [CSMain.sharedInstance asyncWith:^{
        self.clipboardGeneration += 1;
        [self.clipboardReadCache removeAllObjects];
        [self.clipboardRequestsInFlight removeAllObjects];
        self.hostClipboardOfferedType = VD_AGENT_CLIPBOARD_UTF8_TEXT;
        if (!self.main || !self.shareClipboard || self.sessionReadOnly) {
            return;
        }
        if (spice_main_channel_agent_test_capability(self.main, VD_AGENT_CAP_CLIPBOARD_BY_DEMAND)) {
            guint32 type = VD_AGENT_CLIPBOARD_UTF8_TEXT;
            spice_main_channel_clipboard_selection_grab(self.main, VD_AGENT_CLIPBOARD_SELECTION_CLIPBOARD, &type, 1);
        }
    }];
}

#pragma mark - Instance methods

- (void)setShareClipboard:(BOOL)shareClipboard {
    if (_shareClipboard == shareClipboard) {
        return;
    }
    _shareClipboard = shareClipboard;
    self.clipboardGeneration += 1;
    [self.clipboardReadCache removeAllObjects];
    [self.clipboardRequestsInFlight removeAllObjects];
    // Any responses to requests made under the previous state are stale, even
    // if sharing is enabled again before those responses arrive.
    self.guestClipboardGeneration = 0;
}

- (BOOL)sessionReadOnly {
    return spice_session_get_read_only(_session);
}
        
/* This will convert line endings if needed (between Windows/Unix conventions),
 * and will make sure 'len' does not take into account any trailing \0 as this could
 * cause some confusion guest side.
 * The 'len' argument will be modified by this function to the length of the modified
 * string
 */
- (NSString *)fixupClipboardText:(NSString *)text {
    if (spice_main_channel_agent_test_capability(self.main,
                                                 VD_AGENT_CAP_GUEST_LINEEND_CRLF)) {
        char *conv = NULL;
        conv = spice_unix2dos([text cStringUsingEncoding:NSUTF8StringEncoding], text.length);
        text = [NSString stringWithUTF8String:conv];
        g_free(conv);
    }
    return text;
}

@end
