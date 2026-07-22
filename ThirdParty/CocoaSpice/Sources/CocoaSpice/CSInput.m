//
// Copyright © 2022 osy. All rights reserved.
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

#import "CSInput.h"
#import "CSChannel+Protected.h"
#import "CocoaSpice.h"
#import <glib.h>
#import <spice-client.h>
#import <spice/protocol.h>

typedef NS_ENUM(NSUInteger, _CSInputPointerKind) {
    _CSInputPointerKindRelative,
    _CSInputPointerKindAbsolute,
};

@interface _CSInputPointerBatch : NSObject

@property (nonatomic) _CSInputPointerKind kind;
@property (nonatomic) CGPoint point;
@property (nonatomic) CSInputButton buttonMask;
@property (nonatomic) NSInteger monitorID;

@end

@implementation _CSInputPointerBatch
@end

@interface _CSInputScrollBatch : NSObject

@property (nonatomic) CGFloat deltaY;
@property (nonatomic) CSInputButton buttonMask;

@end


@implementation _CSInputScrollBatch
@end

@interface CSInput ()

@property (nonatomic, readwrite) SpiceInputsChannel *channel;

- (void)enqueueBoundaryWithBlock:(dispatch_block_t)block;
- (void)enqueueCoalescedPointer:(_CSInputPointerKind)kind
                           point:(CGPoint)point
                      buttonMask:(CSInputButton)buttonMask
                       monitorID:(NSInteger)monitorID;
- (void)enqueueCoalescedScroll:(CSInputScroll)type
                        deltaY:(CGFloat)deltaY
                    buttonMask:(CSInputButton)buttonMask;

@end

@implementation CSInput {
    CGFloat                 _scroll_delta_y;
    _CSInputPointerBatch    *_pendingPointerBatch;
    _CSInputScrollBatch     *_pendingScrollBatch;
    NSUInteger              _pendingInputSubmissionCount;

    uint32_t                _key_state[512 / 32];
}

#pragma mark - Properties

- (SpiceChannel *)spiceChannel {
    return SPICE_CHANNEL(self.channel);
}

- (BOOL)serverModeCursor {
    enum SpiceMouseMode mouse_mode;
    
    if (!self.spiceMain) {
        return NO;
    }
    g_object_get(self.spiceMain, "mouse-mode", &mouse_mode, NULL);
    return (mouse_mode == SPICE_MOUSE_MODE_SERVER);
}

#pragma mark - Key handling

- (void)sendPause:(CSInputKey)type {
    if (!self.channel) {
        return;
    }
    [self enqueueBoundaryWithBlock:^{
        SpiceInputsChannel *inputs = self.channel;
        /* Send proper scancodes. This will send same scancodes
         * as hardware.
         * The 0x21d is a sort of Third-Ctrl while
         * 0x45 is the NumLock.
         */
        if (type == kCSInputKeyPress) {
            spice_inputs_channel_key_press(inputs, 0x21d);
            spice_inputs_channel_key_press(inputs, 0x45);
        } else {
            spice_inputs_channel_key_release(inputs, 0x21d);
            spice_inputs_channel_key_release(inputs, 0x45);
        }
    }];
}

- (void)sendKey:(CSInputKey)type code:(int)scancode {
    uint32_t i, b, m;
    
    g_return_if_fail(scancode != 0);
    
    if (!self.channel) {
        return;
    }
    if (self.disableInputs) {
        return;
    }
    
    i = scancode / 32;
    b = scancode % 32;
    m = (1u << b);
    g_return_if_fail(i < SPICE_N_ELEMENTS(self->_key_state));
    
    [self enqueueBoundaryWithBlock:^{
        SpiceInputsChannel *inputs = self.channel;
        switch (type) {
            case kCSInputKeyPress:
                spice_inputs_channel_key_press(inputs, scancode);
                
                self->_key_state[i] |= m;
                break;
                
            case kCSInputKeyRelease:
                if (!(self->_key_state[i] & m))
                    break;
                
                
                spice_inputs_channel_key_release(inputs, scancode);
                
                self->_key_state[i] &= ~m;
                break;
                
            default:
                g_warn_if_reached();
        }
    }];
}

- (void)releaseKeys {
    uint32_t i, b;
    
    SPICE_DEBUG("%s", __FUNCTION__);
    for (i = 0; i < SPICE_N_ELEMENTS(self->_key_state); i++) {
        if (!self->_key_state[i]) {
            continue;
        }
        for (b = 0; b < 32; b++) {
            unsigned int scancode = i * 32 + b;
            if (scancode != 0) {
                [self sendKey:kCSInputKeyRelease code:scancode];
            }
        }
    }
}

- (CSInputKeyLock)keyLock {
    guint32 locks;
    CSInputKeyLock keyLock = 0;
    
    if (!self.channel) {
        return kCSInputKeyLockNone;
    }
    g_object_get(self.channel, "key-modifiers", &locks, NULL);
    if (locks & SPICE_INPUTS_NUM_LOCK) {
        keyLock |= kCSInputKeyLockNum;
    }
    if (locks & SPICE_INPUTS_CAPS_LOCK) {
        keyLock |= kCSInputKeyLockCaps;
    }
    if (locks & SPICE_INPUTS_SCROLL_LOCK) {
        keyLock |= kCSInputKeyLockScroll;
    }
    return keyLock;
}

- (void)setKeyLock:(CSInputKeyLock)keyLock {
    guint locks = 0;
    
    if (!self.channel) {
        return;
    }
    if (keyLock & kCSInputKeyLockNum) {
        locks |= SPICE_INPUTS_NUM_LOCK;
    }
    if (keyLock & kCSInputKeyLockCaps) {
        locks |= SPICE_INPUTS_CAPS_LOCK;
    }
    if (keyLock & kCSInputKeyLockScroll) {
        locks |= SPICE_INPUTS_SCROLL_LOCK;
    }
    
    [self enqueueBoundaryWithBlock:^{
        spice_inputs_channel_set_key_locks(self.channel, locks);
    }];
}

#pragma mark - Mouse handling

static int cs_button_mask_to_spice(CSInputButton button)
{
    int spice = 0;
    
    if (button & kCSInputButtonLeft)
        spice |= SPICE_MOUSE_BUTTON_MASK_LEFT;
    if (button & kCSInputButtonMiddle)
        spice |= SPICE_MOUSE_BUTTON_MASK_MIDDLE;
    if (button & kCSInputButtonRight)
        spice |= SPICE_MOUSE_BUTTON_MASK_RIGHT;
    if (button & kCSInputButtonUp)
        spice |= SPICE_MOUSE_BUTTON_MASK_UP;
    if (button & kCSInputButtonDown)
        spice |= SPICE_MOUSE_BUTTON_MASK_DOWN;
    if (button & kCSInputButtonSide)
        spice |= SPICE_MOUSE_BUTTON_MASK_SIDE;
    if (button & kCSInputButtonExtra)
        spice |= SPICE_MOUSE_BUTTON_MASK_EXTRA;
    return spice;
}

static int cs_button_to_spice(CSInputButton button)
{
    int spice = 0;
    
    if (button & kCSInputButtonLeft)
        spice |= SPICE_MOUSE_BUTTON_LEFT;
    if (button & kCSInputButtonMiddle)
        spice |= SPICE_MOUSE_BUTTON_MIDDLE;
    if (button & kCSInputButtonRight)
        spice |= SPICE_MOUSE_BUTTON_RIGHT;
    if (button & kCSInputButtonUp)
        spice |= SPICE_MOUSE_BUTTON_UP;
    if (button & kCSInputButtonDown)
        spice |= SPICE_MOUSE_BUTTON_DOWN;
    if (button & kCSInputButtonSide)
        spice |= SPICE_MOUSE_BUTTON_SIDE;
    if (button & kCSInputButtonExtra)
        spice |= SPICE_MOUSE_BUTTON_EXTRA;
    return spice;
}

/// Stop later motion from being folded into the batch queued before a key,
/// button, scroll, or mouse-mode event. This preserves FIFO event boundaries
/// while still bounding consecutive pointer motion to one GLib submission.
- (void)enqueueBoundaryWithBlock:(dispatch_block_t)block {
    @synchronized (self) {
        _pendingPointerBatch = nil;
        _pendingScrollBatch = nil;
        [CSMain.sharedInstance asyncWith:block];
    }
}

- (void)enqueueCoalescedPointer:(_CSInputPointerKind)kind
                           point:(CGPoint)point
                      buttonMask:(CSInputButton)buttonMask
                       monitorID:(NSInteger)monitorID {
    _CSInputPointerBatch *batch;

    @synchronized (self) {
        _pendingScrollBatch = nil;
        batch = _pendingPointerBatch;
        BOOL needsSubmission = NO;
        if (!batch || batch.kind != kind || batch.monitorID != monitorID) {
            if (_pendingInputSubmissionCount >= 32) {
                return;
            }
            batch = [_CSInputPointerBatch new];
            batch.kind = kind;
            batch.monitorID = monitorID;
            _pendingPointerBatch = batch;
            _pendingInputSubmissionCount += 1;
            needsSubmission = YES;
        }
        if (kind == _CSInputPointerKindRelative) {
            batch.point = CGPointMake(batch.point.x + point.x, batch.point.y + point.y);
        } else {
            batch.point = point;
        }
        batch.buttonMask = buttonMask;
        if (needsSubmission) {
            [CSMain.sharedInstance asyncWith:^{
                CGPoint coalescedPoint;
                CSInputButton coalescedButtonMask;
                NSInteger coalescedMonitorID;
                @synchronized (self) {
                    if (self->_pendingInputSubmissionCount > 0) {
                        self->_pendingInputSubmissionCount -= 1;
                    }
                    coalescedPoint = batch.point;
                    coalescedButtonMask = batch.buttonMask;
                    coalescedMonitorID = batch.monitorID;
                    if (self->_pendingPointerBatch == batch) {
                        self->_pendingPointerBatch = nil;
                    }
                }

                if (kind == _CSInputPointerKindRelative) {
                    if (self.serverModeCursor) {
                        spice_inputs_channel_motion(self.channel,
                                                    coalescedPoint.x,
                                                    coalescedPoint.y,
                                                    cs_button_mask_to_spice(coalescedButtonMask));
                    }
                } else if (!self.serverModeCursor) {
                    spice_inputs_channel_position(self.channel,
                                                  coalescedPoint.x,
                                                  coalescedPoint.y,
                                                  (int)coalescedMonitorID,
                                                  cs_button_mask_to_spice(coalescedButtonMask));
                }
            }];
        }
    }
}

- (void)enqueueCoalescedScroll:(CSInputScroll)type
                        deltaY:(CGFloat)deltaY
                    buttonMask:(CSInputButton)buttonMask {
    _CSInputScrollBatch *batch;
    @synchronized (self) {
        _pendingPointerBatch = nil;
        batch = _pendingScrollBatch;
        BOOL needsSubmission = NO;
        if (!batch) {
            if (_pendingInputSubmissionCount >= 32) {
                return;
            }
            batch = [_CSInputScrollBatch new];
            _pendingScrollBatch = batch;
            _pendingInputSubmissionCount += 1;
            needsSubmission = YES;
        }
        if (type == kCSInputScrollUp) {
            batch.deltaY -= 1;
        } else if (type == kCSInputScrollDown) {
            batch.deltaY += 1;
        } else {
            batch.deltaY += deltaY;
        }
        batch.buttonMask = buttonMask;
        if (needsSubmission) {
            [CSMain.sharedInstance asyncWith:^{
                CGFloat coalescedDeltaY;
                CSInputButton coalescedButtonMask;
                @synchronized (self) {
                    if (self->_pendingInputSubmissionCount > 0) {
                        self->_pendingInputSubmissionCount -= 1;
                    }
                    coalescedDeltaY = batch.deltaY;
                    coalescedButtonMask = batch.buttonMask;
                    if (self->_pendingScrollBatch == batch) {
                        self->_pendingScrollBatch = nil;
                    }
                }
                gint buttonState = cs_button_mask_to_spice(coalescedButtonMask);
                // Bound work in one GLib callback. Under an extreme burst, keep
                // the newest direction but drop excess steps rather than blocking
                // input, display, and clipboard processing behind thousands of
                // synthetic button events.
                self->_scroll_delta_y = MAX(-32, MIN(32, self->_scroll_delta_y + coalescedDeltaY));
                while (ABS(self->_scroll_delta_y) >= 1) {
                    gint button = self->_scroll_delta_y < 0
                        ? SPICE_MOUSE_BUTTON_UP
                        : SPICE_MOUSE_BUTTON_DOWN;
                    spice_inputs_channel_button_press(self.channel, button, buttonState);
                    spice_inputs_channel_button_release(self.channel, button, buttonState);
                    self->_scroll_delta_y += self->_scroll_delta_y < 0 ? 1 : -1;
                }
            }];
        }
    }
}

- (void)sendMouseMotion:(CSInputButton)buttonMask relativePoint:(CGPoint)relativePoint forMonitorID:(NSInteger)monitorID {
    if (!self.channel) {
        return;
    }
    if (self.disableInputs) {
        return;
    }
    
    [self enqueueCoalescedPointer:_CSInputPointerKindRelative
                            point:relativePoint
                       buttonMask:buttonMask
                        monitorID:monitorID];
}

- (void)sendMouseMotion:(CSInputButton)buttonMask relativePoint:(CGPoint)relativePoint {
    [self sendMouseMotion:buttonMask relativePoint:relativePoint forMonitorID:0];
}

- (void)sendMousePosition:(CSInputButton)buttonMask absolutePoint:(CGPoint)absolutePoint forMonitorID:(NSInteger)monitorID {
    if (!self.channel) {
        return;
    }
    if (self.disableInputs) {
        return;
    }
    
    [self enqueueCoalescedPointer:_CSInputPointerKindAbsolute
                            point:absolutePoint
                       buttonMask:buttonMask
                        monitorID:monitorID];
}

- (void)sendMousePosition:(CSInputButton)buttonMask absolutePoint:(CGPoint)absolutePoint {
    [self sendMousePosition:buttonMask absolutePoint:absolutePoint forMonitorID:0];
}

- (void)sendMouseScroll:(CSInputScroll)type buttonMask:(CSInputButton)buttonMask dy:(CGFloat)dy {
    SPICE_DEBUG("%s", __FUNCTION__);
    
    if (!self.channel) {
        return;
    }
    if (self.disableInputs) {
        return;
    }

    [self enqueueCoalescedScroll:type deltaY:dy buttonMask:buttonMask];
}

- (void)sendMouseButton:(CSInputButton)button mask:(CSInputButton)mask pressed:(BOOL)pressed {
    SPICE_DEBUG("%s %s: button %u", __FUNCTION__,
                  pressed ? "press" : "release",
                  (unsigned int)button);
    
    if (!self.channel) {
        return;
    }
    if (self.disableInputs) {
        return;
    }
    
    [self enqueueBoundaryWithBlock:^{
        SpiceInputsChannel *inputs = self.channel;
        if (pressed) {
            spice_inputs_channel_button_press(inputs,
                                              cs_button_to_spice(button),
                                              cs_button_mask_to_spice(mask));
        } else {
            spice_inputs_channel_button_release(inputs,
                                                cs_button_to_spice(button),
                                                cs_button_mask_to_spice(mask));
        }
    }];
}

- (void)requestMouseMode:(BOOL)server {
    if (!self.spiceMain) {
        return;
    }
    [self enqueueBoundaryWithBlock:^{
        SpiceMainChannel *main = self.spiceMain;
        if (server) {
            spice_main_channel_request_mouse_mode(main, SPICE_MOUSE_MODE_SERVER);
        } else {
            spice_main_channel_request_mouse_mode(main, SPICE_MOUSE_MODE_CLIENT);
        }
    }];
}

#pragma mark - Initializers

- (instancetype)initWithChannel:(SpiceInputsChannel *)channel {
    self = [self init];
    if (self) {
        self.channel = g_object_ref(channel);
    }
    return self;
}

- (void)dealloc {
    [CSMain.sharedInstance syncWith:^{
        g_object_unref(self.channel);
    }];
}

@end
