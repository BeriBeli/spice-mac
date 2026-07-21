import XCTest
@testable import SpiceClipboardLogic

final class ClipboardSharingGateTests: XCTestCase {
    func testDisabledGateDoesNotIssueTokens() {
        let gate = ClipboardSharingGate()
        XCTAssertNil(gate.tokenIfEnabled())
    }

    func testDisableInvalidatesQueuedWrite() throws {
        let gate = ClipboardSharingGate()
        gate.setEnabled(true)
        let queuedWrite = try XCTUnwrap(gate.tokenIfEnabled())

        gate.setEnabled(false)

        XCTAssertFalse(gate.accepts(queuedWrite))
    }

    func testReenableDoesNotReviveWriteFromPreviousGeneration() throws {
        let gate = ClipboardSharingGate()
        gate.setEnabled(true)
        let staleWrite = try XCTUnwrap(gate.tokenIfEnabled())

        gate.setEnabled(false)
        gate.setEnabled(true)
        let currentWrite = try XCTUnwrap(gate.tokenIfEnabled())

        XCTAssertFalse(gate.accepts(staleWrite))
        XCTAssertTrue(gate.accepts(currentWrite))
    }

    func testRepeatedEnableKeepsCurrentGenerationValid() throws {
        let gate = ClipboardSharingGate()
        gate.setEnabled(true)
        let currentWrite = try XCTUnwrap(gate.tokenIfEnabled())

        gate.setEnabled(true)

        XCTAssertTrue(gate.accepts(currentWrite))
    }
}
