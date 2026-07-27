import Foundation
import XCTest

/// Source-contract tests for the three strongest client-side stutter risks.
///
/// These pin the queueing and completion invariants without requiring a live
/// guest, a particular mouse, or timing-sensitive benchmarks.
final class StutterRiskRegressionTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8)
    }

    private func slice(
        _ source: String,
        from start: String,
        through end: String
    ) throws -> Substring {
        let startIndex = try XCTUnwrap(source.range(of: start)?.lowerBound)
        let endSearchStart = source.index(startIndex, offsetBy: start.count)
        let endIndex = try XCTUnwrap(
            source.range(of: end, range: endSearchStart..<source.endIndex)?.upperBound
        )
        return source[startIndex..<endIndex]
    }

    func testHighFrequencyPointerMotionIsCoalescedBeforeEnteringSpiceMainContext() throws {
        let input = try source("ThirdParty/CocoaSpice/Sources/CocoaSpice/CSInput.m")
        let method = try slice(
            input,
            from: "- (void)sendMouseMotion:(CSInputButton)buttonMask relativePoint:(CGPoint)relativePoint forMonitorID:(NSInteger)monitorID {",
            through: "\n}"
        )

        XCTAssertTrue(
            method.contains("enqueueCoalescedPointer"),
            "The high-frequency path needs an explicit bounded coalescing policy."
        )
        XCTAssertFalse(
            method.contains("asyncWith:"),
            "One GLib submission per pointer event permits an unbounded backlog."
        )

        let implementationStart = try XCTUnwrap(
            input.range(of: "- (void)enqueueCoalescedPointer:", options: .backwards)?.lowerBound
        )
        let coalescer = input[implementationStart...]
        let lock = try XCTUnwrap(coalescer.range(of: "@synchronized (self)"))
        let submission = try XCTUnwrap(
            coalescer.range(of: "asyncUserInteractiveWith:")
        )
        XCTAssertLessThan(
            lock.lowerBound,
            submission.lowerBound,
            "Batch mutation and GLib submission need one FIFO linearization point."
        )
    }

    func testInputSubmissionsRunAheadOfNormalSpiceWork() throws {
        let main = try source("ThirdParty/CocoaSpice/Sources/CocoaSpice/CSMain.m")
        let interactiveMethod = try slice(
            main,
            from: "- (void)asyncUserInteractiveWith:(dispatch_block_t)block {",
            through: "\n}"
        )
        XCTAssertTrue(
            interactiveMethod.contains("G_PRIORITY_HIGH"),
            "User input must not wait behind normal-priority display and network work."
        )
        XCTAssertTrue(main.contains("CSInteractiveBurstLimit = 8"))
        XCTAssertTrue(main.contains("g_idle_source_new()"))
        XCTAssertTrue(main.contains("g_source_attach(source, self.glibMainContext)"))
        XCTAssertTrue(
            main.contains("scheduleInteractiveDrainWithPriority:G_PRIORITY_DEFAULT"),
            "Sustained input must yield to normal-priority socket and display work."
        )

        let header = try source(
            "ThirdParty/CocoaSpice/Sources/CocoaSpice/include/CSMain.h"
        )
        XCTAssertFalse(
            header.contains("asyncUserInteractiveWith"),
            "Input scheduling is an internal policy, not a public CSMain escape hatch."
        )

        let input = try source("ThirdParty/CocoaSpice/Sources/CocoaSpice/CSInput.m")
        XCTAssertFalse(
            input.contains("CSMain.sharedInstance asyncWith:"),
            "Every CSInput submission must use the latency-sensitive GLib path."
        )
        XCTAssertEqual(
            input.components(separatedBy: "CSMain.sharedInstance asyncUserInteractiveWith:").count - 1,
            3,
            "Boundary, pointer, and scroll submissions must share one priority and preserve FIFO ordering."
        )
    }

    func testKeyboardTransitionsUseDedicatedLosslessSubmissionPath() throws {
        let input = try source("ThirdParty/CocoaSpice/Sources/CocoaSpice/CSInput.m")
        let method = try slice(
            input,
            from: "- (void)sendKey:(CSInputKey)type code:(int)scancode {",
            through: "\n}"
        )

        XCTAssertFalse(
            method.contains("enqueueBoundaryWithBlock"),
            "Keyboard transitions must not share the generic burst drain, where a saturated input stream can drop press/release pairs."
        )
        XCTAssertTrue(
            method.contains("enqueueKeyboard"),
            "Keyboard transitions need a dedicated lossless FIFO submission path."
        )

        let main = try source("ThirdParty/CocoaSpice/Sources/CocoaSpice/CSMain.m")
        XCTAssertTrue(
            main.contains("- (void)asyncKeyboardWith:(dispatch_block_t)block {"),
            "The keyboard FIFO must be independent from the generic interactive burst queue."
        )
        let drain = try slice(
            main,
            from: "- (void)drainNextKeyboardBlock {",
            through: "\n}"
        )
        XCTAssertTrue(drain.contains("removeObjectAtIndex:0"))
        XCTAssertFalse(
            drain.contains("for ("),
            "Only one keyboard transition may be submitted per GLib iteration."
        )
    }

    func testKeyEventsRecoverModifiersWhenFlagsChangedIsMissing() throws {
        let router = try source(
            "Packages/SpiceController/Sources/SpiceController/SpiceInputRouter.swift"
        )
        let keyDown = try slice(
            router,
            from: "public func keyDown(_ event: NSEvent) {",
            through: "\n    }"
        )
        let synthesize = try XCTUnwrap(
            keyDown.range(of: "synthesizeMissingModifiers")
        )
        let press = try XCTUnwrap(
            keyDown.range(of: "sendKey(event.keyCode, pressed: true)")
        )
        XCTAssertLessThan(
            synthesize.lowerBound,
            press.lowerBound,
            "A modifier present only in keyDown.modifierFlags must be pressed before the ordinary key."
        )

        let keyUp = try slice(
            router,
            from: "public func keyUp(_ event: NSEvent) {",
            through: "\n    }"
        )
        let releaseKey = try XCTUnwrap(
            keyUp.range(of: "sendKey(event.keyCode, pressed: false)")
        )
        let releaseSynthetic = try XCTUnwrap(
            keyUp.range(of: "releaseSyntheticModifiers")
        )
        XCTAssertLessThan(
            releaseKey.lowerBound,
            releaseSynthetic.lowerBound,
            "A synthesized modifier must remain held through the ordinary key release."
        )
    }

    func testClipboardRequestDoesNotSynchronouslyReadAppKitPasteboardOnSpiceThread() throws {
        let session = try source("ThirdParty/CocoaSpice/Sources/CocoaSpice/CSSession.m")
        let callback = try slice(
            session,
            from: "static gboolean cs_clipboard_request(",
            through: "\n}"
        )

        let hop = try XCTUnwrap(callback.range(of: "dispatch_async(dispatch_get_main_queue()"))
        let read = try XCTUnwrap(callback.range(of: "[self.pasteboardDelegate dataForType:"))
        XCTAssertLessThan(
            hop.lowerBound,
            read.lowerBound,
            "The SPICE callback must leave the GLib thread before materializing pasteboard data."
        )
        XCTAssertTrue(
            callback.contains("clipboardRequestsInFlight"),
            "Guest requests must be deduplicated before dispatching work to the main thread."
        )
        XCTAssertTrue(
            callback.contains("cs_clipboard_type_is_supported(type)"),
            "Unknown guest-controlled types must not create new in-flight keys."
        )
        XCTAssertTrue(callback.contains("clipboardReadsOutstanding >= 5"))
        XCTAssertTrue(callback.contains("type != self.hostClipboardOfferedType"))
        XCTAssertTrue(
            callback.contains("(unsigned long)generation"),
            "A new clipboard generation must not be deduplicated against stale work."
        )
        XCTAssertTrue(
            callback.contains("clipboardReadCache[@(type)]"),
            "Repeated requests in one host clipboard generation must reuse a snapshot."
        )
        XCTAssertTrue(
            callback.contains("self.main == main"),
            "A delayed read must never notify a disconnected main channel."
        )
    }

    func testCanvasBlitCompletionDoesNotWaitForDisplayPresentation() throws {
        let renderer = try source(
            "ThirdParty/CocoaSpice/Sources/CocoaSpiceRenderer/CSMetalRenderer.m"
        )
        let method = try slice(
            renderer,
            from: "- (void)renderSouce:(id<CSRenderSource>)renderSource",
            through: "\n}"
        )

        XCTAssertTrue(
            method.contains("addCompletedHandler"),
            "The canvas producer should receive completion from the submitted blit."
        )
        XCTAssertFalse(
            method.contains("[self _addDrawCompletion:completion]"),
            "Producer completion must not wait for a later display presentation."
        )
        XCTAssertTrue(
            method.contains("dispatch_async(dispatch_get_main_queue(), completion)"),
            "The exported completion callback must retain its main-thread delivery contract."
        )
    }

    func testHighFrequencyScrollIsCoalescedBeforeEnteringSpiceMainContext() throws {
        let input = try source("ThirdParty/CocoaSpice/Sources/CocoaSpice/CSInput.m")
        let method = try slice(
            input,
            from: "- (void)sendMouseScroll:(CSInputScroll)type",
            through: "\n}"
        )

        XCTAssertTrue(method.contains("enqueueCoalescedScroll"))
        XCTAssertFalse(method.contains("asyncWith:"))
        XCTAssertTrue(
            input.contains("MAX(-32, MIN(32"),
            "A coalesced burst must not monopolize the GLib context while draining."
        )
        XCTAssertTrue(
            input.contains("_pendingInputSubmissionCount >= 32"),
            "Alternating pointer and scroll kinds must not bypass queue bounds."
        )
    }

    func testRendererClearsDirtyFlagAfterSubmittingAFrame() throws {
        let renderer = try source(
            "ThirdParty/CocoaSpice/Sources/CocoaSpiceRenderer/CSMetalRenderer.m"
        )
        let method = try slice(
            renderer,
            from: "- (void)drawInMTKView:(nonnull MTKView *)view",
            through: "\n}"
        )

        XCTAssertTrue(
            method.contains("self.renderNeedsUpdate = NO"),
            "A single damage must not keep submitting unchanged GPU frames forever."
        )
        XCTAssertTrue(
            method.contains("_takeDrawCompletions"),
            "Each submitted frame must own only the completions present at submission."
        )
    }

    func testCanvasProducerDoesNotWaitForSecondaryRendererPresentation() throws {
        let displayRenderer = try source(
            "ThirdParty/CocoaSpice/Sources/CocoaSpice/CSDisplay+Renderer.m"
        )
        let method = try slice(
            displayRenderer,
            from: "- (void)copyBuffer:(id<MTLBuffer>)sourceBuffer",
            through: "\n}"
        )

        XCTAssertTrue(method.contains("renderers.count == 0"))
        XCTAssertTrue(method.contains("completion:completion"))
        XCTAssertTrue(method.contains("withCompletion:nil"))

        let renderer = try source(
            "ThirdParty/CocoaSpice/Sources/CocoaSpiceRenderer/CSMetalRenderer.m"
        )
        XCTAssertTrue(
            renderer.contains("sharedCommandQueueForTexture"),
            "Shared textures require one GPU ordering domain across renderers."
        )
    }

    func testEmptyRendererInvalidationStillCompletesTeardown() throws {
        let displayRenderer = try source(
            "ThirdParty/CocoaSpice/Sources/CocoaSpice/CSDisplay+Renderer.m"
        )
        let method = try slice(
            displayRenderer,
            from: "- (void)invalidateWithCompletion:(completionCallback_t)completion",
            through: "\n}"
        )

        XCTAssertTrue(method.contains("renderers.count == 0"))
        XCTAssertTrue(method.contains("completion();"))
    }

}
