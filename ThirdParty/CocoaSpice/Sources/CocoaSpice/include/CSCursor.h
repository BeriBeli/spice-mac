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

#import "CSChannel.h"
@import CocoaSpiceRenderer;

@class CSDisplay;

NS_ASSUME_NONNULL_BEGIN

/// An immutable, coherent view of the guest cursor at one revision.
///
/// The snapshot object is published atomically by `CSCursor`, so consumers must
/// retain and use one instance rather than reading live cursor fields separately.
@interface CSCursorSnapshot : NSObject

/// Current cursor pixels in normalized premultiplied RGBA byte order, or nil
/// when the guest requests its default cursor.
@property (nonatomic, nullable, readonly, copy) NSData *cursorImageData;

/// Pixel size and hot spot for `cursorImageData`.
@property (nonatomic, readonly) CGSize cursorSize;
@property (nonatomic, readonly) CGPoint cursorHotspot;

/// Whether the guest explicitly hid its cursor.
@property (nonatomic, readonly) BOOL cursorHidden;

/// Whether SPICE is using server (relative) mouse mode.
@property (nonatomic, readonly) BOOL serverModeCursor;

/// Monotonically increasing cursor-state revision.
@property (nonatomic, readonly) NSUInteger cursorRevision;

- (instancetype)init NS_UNAVAILABLE;

@end

/// Handles cursor rendering
///
/// This implements the `CSRenderSource` protocol which can be used to render to a Metal device.
@interface CSCursor : CSChannel <CSRenderSource>

/// Atomically replaced after cursor set/hide/reset, visibility-restoring moves,
/// and mouse-mode transitions. Observe this property for native presentation.
@property (atomic, readonly, strong) CSCursorSnapshot *snapshot;

/// Set this to true to not render the cursor only if client side cusor rendering is supported.
/// If it is not supported, this will do nothing.
@property (nonatomic, assign) BOOL isInhibited;

/// Cursor is visible if it is not inhibited (by the host) and is not hidden (by the guest) and is drawn (by the guest)
@property (nonatomic, readonly) BOOL isVisible;

- (instancetype)init NS_UNAVAILABLE;

/// Set the cursor to a new location (only appliable if client side cursor rendering is in use)
/// @param point Point relative to the display
- (void)moveTo:(CGPoint)point NS_SWIFT_NAME(move(to:));

@end

NS_ASSUME_NONNULL_END
