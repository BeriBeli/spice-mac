import CoreGraphics
import Foundation
import XCTest
@testable import SpiceCursorLogic

final class SpiceCursorRegressionTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testNativeCursorPreservesRGBAChannels() throws {
        // spice-gtk publishes normalized RGBA bytes. A red source pixel must
        // remain red after the CGImage interpretation used by AppKit.
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

    func testNativePresentationConsumesOneAtomicSnapshotContract() throws {
        let header = try String(contentsOf: repositoryRoot.appendingPathComponent(
            "ThirdParty/CocoaSpice/Sources/CocoaSpice/include/CSCursor.h"
        ))
        let view = try String(contentsOf: repositoryRoot.appendingPathComponent(
            "Sources/SpiceMac/SpiceDisplayView.swift"
        ))

        XCTAssertTrue(header.contains("@property (atomic, readonly, strong) CSCursorSnapshot *snapshot;"))
        XCTAssertTrue(view.contains("observe(\\.snapshot"))
        XCTAssertFalse(view.contains("observe(\\.cursorRevision"))
        XCTAssertTrue(view.contains("makeNativeCursor(from snapshot: CSCursorSnapshot)"))
    }

    func testCursorChannelDestroyDetachesDisplayCursor() throws {
        let connection = try String(contentsOf: repositoryRoot.appendingPathComponent(
            "ThirdParty/CocoaSpice/Sources/CocoaSpice/CSConnection.m"
        ))

        XCTAssertTrue(connection.contains("SPICE_IS_CURSOR_CHANNEL(channel)"))
        XCTAssertTrue(connection.contains("display.cursor = nil;"))
    }

    func testCursorMoveRestoresHiddenDefaultCursorContract() throws {
        let cursor = try String(contentsOf: repositoryRoot.appendingPathComponent(
            "ThirdParty/CocoaSpice/Sources/CocoaSpice/CSCursor.m"
        ))

        XCTAssertTrue(cursor.contains("BOOL visibilityChanged = self.cursorHidden;"))
        XCTAssertTrue(cursor.contains("self.cursorHidden = NO;"))
        XCTAssertFalse(cursor.contains("BOOL visibilityChanged = self.hasCursor && self.cursorHidden;"))
    }
}
