import CocoaSpice
import Foundation
import XCTest

final class CSMainLatencyDiagnosticsTests: XCTestCase {
    func testObserverSeparatesQueueWaitFromExecutionTime() throws {
        let main = CSMain.shared
        XCTAssertTrue(main.running || main.spiceStart())

        let blockerStarted = DispatchSemaphore(value: 0)
        let releaseBlocker = DispatchSemaphore(value: 0)
        let targetExecuted = expectation(description: "target block executed")
        let targetMeasured = expectation(description: "target timing reported")
        let samplesLock = NSLock()
        var targetSample: (queueWait: TimeInterval, execution: TimeInterval)?

        main.latencyObserver = { label, queueWait, executionTime in
            guard label == "test.queue-target" else { return }
            XCTAssertFalse(main.isCurrentContextMain)
            samplesLock.lock()
            targetSample = (queueWait, executionTime)
            samplesLock.unlock()
            targetMeasured.fulfill()
        }
        defer { main.latencyObserver = nil }

        main.async(label: "test.blocker") {
            blockerStarted.signal()
            _ = releaseBlocker.wait(timeout: .now() + 2)
        }
        XCTAssertEqual(blockerStarted.wait(timeout: .now() + 2), .success)

        main.async(label: "test.queue-target") {
            targetExecuted.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.05)
        releaseBlocker.signal()

        wait(for: [targetExecuted, targetMeasured], timeout: 2)
        samplesLock.lock()
        let sample = targetSample
        samplesLock.unlock()

        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(sample).queueWait,
            0.04,
            "The diagnostic must expose time spent queued behind other GLib work."
        )
        XCTAssertLessThan(
            try XCTUnwrap(sample).execution,
            0.02,
            "A no-op target should not be misclassified as slow execution."
        )
    }

    func testObserverReportsSlowExecutionSeparately() throws {
        let main = CSMain.shared
        XCTAssertTrue(main.running || main.spiceStart())

        let measured = expectation(description: "slow execution timing reported")
        let samplesLock = NSLock()
        var sample: (queueWait: TimeInterval, execution: TimeInterval)?

        main.latencyObserver = { label, queueWait, executionTime in
            guard label == "test.slow-execution" else { return }
            samplesLock.lock()
            sample = (queueWait, executionTime)
            samplesLock.unlock()
            measured.fulfill()
        }
        defer { main.latencyObserver = nil }

        main.async(label: "test.slow-execution") {
            Thread.sleep(forTimeInterval: 0.04)
        }

        wait(for: [measured], timeout: 2)
        samplesLock.lock()
        let captured = sample
        samplesLock.unlock()

        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(captured).execution,
            0.03,
            "Slow work inside the GLib context must be visible as execution time."
        )
    }

    func testQueuedSampleStaysWithObserverActiveAtSubmission() throws {
        let main = CSMain.shared
        XCTAssertTrue(main.running || main.spiceStart())

        let blockerStarted = DispatchSemaphore(value: 0)
        let releaseBlocker = DispatchSemaphore(value: 0)
        let measuredByOriginal = expectation(description: "original observer measured queued work")
        let replacementCalled = expectation(description: "replacement observer not called")
        replacementCalled.isInverted = true

        main.async(label: "test.observer-blocker") {
            blockerStarted.signal()
            _ = releaseBlocker.wait(timeout: .now() + 2)
        }
        XCTAssertEqual(blockerStarted.wait(timeout: .now() + 2), .success)

        main.latencyObserver = { label, _, _ in
            if label == "test.observer-owner" { measuredByOriginal.fulfill() }
        }
        main.async(label: "test.observer-owner") {}
        main.latencyObserver = { label, _, _ in
            if label == "test.observer-owner" { replacementCalled.fulfill() }
        }
        defer { main.latencyObserver = nil }

        releaseBlocker.signal()
        wait(for: [measuredByOriginal, replacementCalled], timeout: 0.3)
    }
}
