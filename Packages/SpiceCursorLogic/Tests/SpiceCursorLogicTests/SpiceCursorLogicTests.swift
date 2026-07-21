import CoreGraphics
import Foundation
import XCTest
@testable import SpiceCursorLogic

private final class WeakBox<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value?) {
        self.value = value
    }
}

final class SpiceCursorLogicTests: XCTestCase {
    func testNativeCursorPreservesRGBAChannels() throws {
        let rgbaRed = Data([255, 0, 0, 255])
        let image = try XCTUnwrap(
            SpiceCursorLogic.makeNativeCursorImage(width: 1, height: 1, data: rgbaRed)
        )

        var rendered = [UInt8](repeating: 0, count: 4)
        let outputInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            .union(.byteOrder32Big)
        let context = try XCTUnwrap(CGContext(
            data: &rendered,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: outputInfo.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        XCTAssertEqual(rendered, [255, 0, 0, 255], "RGBA red must not become blue")
    }

    func testServerModeCustomCursorHasExactlyOneVisiblePath() {
        let decision = SpiceCursorLogic.presentationDecision(
            serverMode: true,
            hidden: false,
            hasCustomShape: true
        )

        XCTAssertEqual(decision.visibleCursorCount(customOverlayVisible: true), 1)
    }

    func testServerModeDefaultCursorStillHasOneVisiblePath() {
        let decision = SpiceCursorLogic.presentationDecision(
            serverMode: true,
            hidden: false,
            hasCustomShape: false
        )

        XCTAssertEqual(
            decision.visibleCursorCount(customOverlayVisible: false),
            1,
            "cursor-set(NULL) and cursor-reset mean default cursor, not no cursor"
        )
    }

    func testClientModeCustomCursorHasExactlyOneVisiblePath() {
        let decision = SpiceCursorLogic.presentationDecision(
            serverMode: false,
            hidden: false,
            hasCustomShape: true
        )

        XCTAssertEqual(decision.visibleCursorCount(customOverlayVisible: true), 1)
    }

    func testExplicitlyHiddenCursorHasNoVisiblePath() {
        let decision = SpiceCursorLogic.presentationDecision(
            serverMode: false,
            hidden: true,
            hasCustomShape: true
        )

        XCTAssertEqual(decision.visibleCursorCount(customOverlayVisible: false), 0)
    }

    func testInactiveWindowShowsOnlySystemCursor() {
        let decision = SpiceCursorLogic.presentationDecision(
            serverMode: true,
            hidden: false,
            hasCustomShape: true,
            windowActive: false
        )

        XCTAssertEqual(decision.hostCursor, .systemDefault)
        XCTAssertTrue(decision.inhibitOverlay)
        XCTAssertEqual(decision.visibleCursorCount(customOverlayVisible: true), 1)
    }

    func testAttachmentSlotRetainsCursorUntilDetach() throws {
        final class Cursor {}

        let slot = CursorAttachmentSlot<Cursor>()
        var cursor: Cursor? = Cursor()
        let weakCursor = WeakBox(cursor)

        XCTAssertTrue(slot.replace(with: cursor))
        cursor = nil

        XCTAssertNotNil(weakCursor.value)
        XCTAssertTrue(slot.value === weakCursor.value)
    }

    func testDetachReleasesCursorAndReportsTransition() {
        final class Cursor {}

        let slot = CursorAttachmentSlot<Cursor>()
        var cursor: Cursor? = Cursor()
        let weakCursor = WeakBox(cursor)
        slot.replace(with: cursor)
        cursor = nil

        XCTAssertTrue(slot.replace(with: nil))
        XCTAssertNil(slot.value)
        XCTAssertNil(weakCursor.value)
    }

    func testReplacingSameCursorIsNotASecondAttachment() throws {
        final class Cursor {}

        let slot = CursorAttachmentSlot<Cursor>()
        let cursor = Cursor()

        XCTAssertTrue(slot.replace(with: cursor))
        XCTAssertFalse(slot.replace(with: cursor))
    }
}
