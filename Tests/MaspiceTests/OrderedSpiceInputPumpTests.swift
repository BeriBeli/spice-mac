// SPDX-License-Identifier: MIT
import Testing
@testable import SpiceController
import SwiftSpice

private actor InputRecorder {
    var inputs: [SpiceClientInput] = []
    func append(_ input: SpiceClientInput) { inputs.append(input) }
}

@Suite("Ordered SPICE input pump")
@MainActor
struct OrderedSpiceInputPumpTests {
    @Test("key and button edges preserve FIFO order")
    func preservesEdges() async {
        let recorder = InputRecorder()
        let pump = OrderedSpiceInputPump(
            send: { await recorder.append($0) },
            onFailure: { _ in Issue.record("unexpected send failure") }
        )

        pump.submit(.keyDown(scanCode: 0x1d))
        pump.submit(.mousePress(.left))
        pump.submit(.mouseRelease(.left))
        pump.submit(.keyUp(scanCode: 0x1d))
        await pump.waitUntilIdle()

        let inputs = await recorder.inputs
        #expect(inputs.count == 4)
        guard inputs.count == 4 else { return }
        if case .keyDown(scanCode: 0x1d) = inputs[0] {} else { Issue.record("missing key down") }
        if case .mousePress(.left) = inputs[1] {} else { Issue.record("missing button down") }
        if case .mouseRelease(.left) = inputs[2] {} else { Issue.record("missing button up") }
        if case .keyUp(scanCode: 0x1d) = inputs[3] {} else { Issue.record("missing key up") }
    }

    @Test("adjacent relative motion is coalesced without crossing an edge")
    func coalescesMotion() async {
        let recorder = InputRecorder()
        let pump = OrderedSpiceInputPump(
            send: { await recorder.append($0) },
            onFailure: { _ in Issue.record("unexpected send failure") }
        )

        pump.submit(.mouseMotion(dx: 2, dy: 3))
        pump.submit(.mouseMotion(dx: 5, dy: -1))
        pump.submit(.mousePress(.left))
        pump.submit(.mouseMotion(dx: 7, dy: 9))
        await pump.waitUntilIdle()

        let inputs = await recorder.inputs
        #expect(inputs.count == 3)
        guard inputs.count == 3 else { return }
        if case .mouseMotion(dx: 7, dy: 2) = inputs[0] {} else { Issue.record("first motion was not coalesced") }
        if case .mousePress(.left) = inputs[1] {} else { Issue.record("edge order changed") }
        if case .mouseMotion(dx: 7, dy: 9) = inputs[2] {} else { Issue.record("motion crossed an edge") }
    }

    @Test("shutdown flushes releases for held keys and buttons")
    func shutdownFlushesReleases() async {
        let recorder = InputRecorder()
        let pump = OrderedSpiceInputPump(
            send: { await recorder.append($0) },
            onFailure: { _ in Issue.record("unexpected send failure") }
        )

        pump.submit(.keyDown(scanCode: 0x2a))
        pump.submit(.mousePress(.right))
        await pump.shutdown()

        let inputs = await recorder.inputs
        #expect(inputs.count == 4)
        guard inputs.count == 4 else { return }
        if case .keyDown(scanCode: 0x2a) = inputs[0] {} else { Issue.record("missing key down") }
        if case .mousePress(.right) = inputs[1] {} else { Issue.record("missing button down") }
        if case .mouseRelease(.right) = inputs[2] {} else { Issue.record("missing button release") }
        if case .keyUp(scanCode: 0x2a) = inputs[3] {} else { Issue.record("missing key release") }
    }
}
