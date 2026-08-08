// SPDX-License-Identifier: MIT
import Testing
@testable import SpiceController
import SwiftSpice

private actor InputRecorder {
    var inputs: [SpiceClientInput] = []
    func append(_ input: SpiceClientInput) { inputs.append(input) }
}

private actor ControlledInputSender {
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func send(_ input: SpiceClientInput) async {
        _ = input
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
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
        let diagnostics = SpiceClientDiagnosticsCollector(enabled: true)
        let pump = OrderedSpiceInputPump(
            send: { await recorder.append($0) },
            diagnostics: diagnostics,
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

        let snapshot = diagnostics.snapshot()
        #expect(snapshot.isEnabled)
        #expect(snapshot.inputSubmitted == 4)
        #expect(snapshot.inputSent == 3)
        #expect(snapshot.inputCoalesced == 1)
        #expect(snapshot.motionSubmitted == 3)
        #expect(snapshot.motionSent == 2)
        #expect(snapshot.pendingInputCount == 0)
        #expect(snapshot.maximumPendingInputCount == 3)
        #expect(snapshot.inputQueueWait.sampleCount == 3)
        #expect(snapshot.inputSendDuration.sampleCount == 3)
        #expect(snapshot.sendFailures == 0)
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

    @Test("diagnostics are disabled by default")
    func diagnosticsDefaultToDisabled() async {
        let diagnostics = SpiceClientDiagnosticsCollector()
        let recorder = InputRecorder()
        let pump = OrderedSpiceInputPump(
            send: { await recorder.append($0) },
            diagnostics: diagnostics,
            onFailure: { _ in Issue.record("unexpected send failure") }
        )

        pump.submit(.mousePosition(x: 10, y: 20, displayID: 0))
        pump.submit(.mousePosition(x: 30, y: 40, displayID: 0))
        await pump.waitUntilIdle()

        #expect(diagnostics.snapshot() == .disabled)
    }

    @Test("collector records session counters and reset keeps enablement")
    func recordsSessionCountersAndResets() {
        let diagnostics = SpiceClientDiagnosticsCollector(enabled: true)
        let firstFrame = ContinuousClock().now

        diagnostics.recordClientFrameEvent(at: firstFrame)
        diagnostics.recordClientFrameEvent(at: firstFrame.advanced(by: .milliseconds(20)))
        diagnostics.recordMouseMotionAcknowledged()
        diagnostics.recordMainActorSchedulingDelay(.milliseconds(75))

        let snapshot = diagnostics.snapshot()
        #expect(snapshot.clientFrameEvents == 2)
        #expect(snapshot.clientFrameEventGap.sampleCount == 1)
        #expect(snapshot.clientFrameEventGap.p95Milliseconds == 20)
        #expect(snapshot.clientFrameEventGap.maximumMilliseconds == 20)
        #expect(snapshot.mouseMotionAcknowledgements == 1)
        #expect(snapshot.mainActorSchedulingDelay.sampleCount == 1)
        #expect(snapshot.mainActorSchedulingDelay.p95Milliseconds == 75)
        #expect(snapshot.mainActorSchedulingDelay.maximumMilliseconds == 75)

        diagnostics.reset()
        let reset = diagnostics.snapshot()
        #expect(reset.isEnabled)
        #expect(reset.clientFrameEvents == 0)
        #expect(reset.clientFrameEventGap == .empty)
        #expect(reset.mouseMotionAcknowledgements == 0)
        #expect(reset.mainActorSchedulingDelay == .empty)
    }

    @Test("collector records content-free VDAgent state and event counts")
    func recordsAgentDiagnosticsWithoutPayloads() {
        let diagnostics = SpiceClientDiagnosticsCollector(enabled: true)
        let unavailable = SpiceDisplayConfigurationSupport(
            agentConnected: false,
            hasExplicitPeerCapabilities: false,
            supportsMonitorConfiguration: false,
            supportsSparseMonitors: false,
            supportsMonitorPositions: false
        )
        diagnostics.seedAgentState(
            support: unavailable,
            clipboardState: .unavailable
        )

        var snapshot = diagnostics.snapshot()
        #expect(snapshot.agent.supportObserved)
        #expect(!snapshot.agent.agentConnected)
        #expect(snapshot.agent.clipboardState == .unavailable)
        #expect(snapshot.agent.agentConnectTransitions == 0)

        let connected = SpiceDisplayConfigurationSupport(
            agentConnected: true,
            hasExplicitPeerCapabilities: true,
            supportsMonitorConfiguration: true,
            supportsSparseMonitors: false,
            supportsMonitorPositions: false
        )
        diagnostics.recordAgentSupport(connected)
        diagnostics.recordClipboardEvent(.ready)
        diagnostics.recordClipboardEvent(.localTextOffered(byteCount: 23))
        diagnostics.recordClipboardEvent(.guestText("not retained"))
        diagnostics.recordClipboardEvent(.oversizedLocalText(byteCount: 42, maximum: 8))
        diagnostics.recordClipboardEvent(.failed(.invalidUTF8))
        diagnostics.recordAgentManagerStartFailure()

        let configuration = SpiceDisplayConfiguration(width: 1_024, height: 768)
        diagnostics.recordMonitorConfigurationRequest(blocked: false)
        diagnostics.recordMonitorConfigurationRequest(blocked: true)
        diagnostics.recordDisplayConfigurationEvent(.queued(configuration))
        diagnostics.recordDisplayConfigurationEvent(.sent(configuration))
        diagnostics.recordDisplayConfigurationEvent(.acknowledged(configuration))
        diagnostics.recordDisplayConfigurationEvent(.rejected(configuration))
        diagnostics.recordDisplayConfigurationEvent(.unsupported(configuration))
        diagnostics.recordDisplayConfigurationEvent(
            .failed(configuration, .unsupportedByAgent)
        )
        diagnostics.recordDisplayConfigurationEvent(
            .protocolFailure(.agentManagerNotRunning)
        )

        snapshot = diagnostics.snapshot()
        #expect(snapshot.agent.agentConnected)
        #expect(snapshot.agent.capabilityAnnouncementReceived)
        #expect(snapshot.agent.monitorConfigurationSupported)
        #expect(snapshot.agent.agentConnectTransitions == 1)
        #expect(snapshot.agent.agentDisconnectTransitions == 0)
        #expect(snapshot.agent.clipboardState == .failed)
        #expect(snapshot.agent.clipboardReadyEvents == 1)
        #expect(snapshot.agent.clipboardLocalTextOfferEvents == 1)
        #expect(snapshot.agent.clipboardGuestTextEvents == 1)
        #expect(snapshot.agent.clipboardOversizedLocalTextEvents == 1)
        #expect(snapshot.agent.clipboardFailures == 1)
        #expect(snapshot.agent.agentManagerStartFailures == 1)
        #expect(snapshot.agent.monitorConfigurationRequests == 2)
        #expect(snapshot.agent.monitorConfigurationBlocked == 1)
        #expect(snapshot.agent.monitorConfigurationQueued == 1)
        #expect(snapshot.agent.monitorConfigurationSent == 1)
        #expect(snapshot.agent.monitorConfigurationAcknowledged == 1)
        #expect(snapshot.agent.monitorConfigurationRejected == 1)
        #expect(snapshot.agent.monitorConfigurationUnsupported == 1)
        #expect(snapshot.agent.monitorConfigurationFailures == 1)
        #expect(snapshot.agent.monitorConfigurationProtocolFailures == 1)

        let finalAgent = snapshot.agent
        diagnostics.setEnabled(false)
        diagnostics.recordClipboardEvent(.guestText("still not retained"))
        #expect(diagnostics.snapshot().agent == finalAgent)
    }

    @Test("collector keeps a SwiftSpice baseline and reset clears the window")
    func recordsAndResetsSwiftSpiceDiagnosticsWindow() {
        let diagnostics = SpiceClientDiagnosticsCollector(enabled: true)
        let firstFrame = ContinuousClock().now

        diagnostics.recordClientFrameEvent(at: firstFrame)
        diagnostics.recordClientFrameEvent(at: firstFrame.advanced(by: .milliseconds(20)))

        diagnostics.recordSwiftSpiceDiagnostics(.empty, sampledAt: firstFrame)
        let baseline = diagnostics.snapshot(
            at: firstFrame.advanced(by: .milliseconds(250))
        ).swiftSpiceDiagnostics
        #expect(baseline?.baseline == .empty)
        #expect(baseline?.latest == .empty)
        #expect(baseline?.latestSampleAgeMilliseconds == 250)
        #expect(diagnostics.snapshot().clientFrameEvents == 0)
        #expect(diagnostics.snapshot().clientFrameEventGap == .empty)

        diagnostics.recordClientFrameEvent(at: firstFrame.advanced(by: .milliseconds(40)))
        #expect(diagnostics.snapshot().clientFrameEvents == 1)
        #expect(diagnostics.snapshot().clientFrameEventGap == .empty)

        diagnostics.recordSwiftSpiceDiagnostics(.empty)
        let updated = diagnostics.snapshot().swiftSpiceDiagnostics
        #expect(updated?.baseline == baseline?.baseline)
        #expect(updated?.latest == .empty)
        #expect(diagnostics.snapshot().clientFrameEvents == 1)

        diagnostics.reset()
        let reset = diagnostics.snapshot()
        #expect(reset.isEnabled)
        #expect(reset.swiftSpiceDiagnostics == nil)

        diagnostics.setEnabled(false)
        diagnostics.recordSwiftSpiceDiagnostics(.empty)
        #expect(diagnostics.snapshot().swiftSpiceDiagnostics == nil)
    }

    @Test("send failures are counted without marking the input sent")
    func recordsSendFailure() async {
        let diagnostics = SpiceClientDiagnosticsCollector(enabled: true)
        let pump = OrderedSpiceInputPump(
            send: { _ in throw SpiceError.protocolError("test failure") },
            diagnostics: diagnostics,
            onFailure: { _ in }
        )

        pump.submit(.keyDown(scanCode: 0x1d))
        await pump.waitUntilIdle()

        let snapshot = diagnostics.snapshot()
        #expect(snapshot.inputSubmitted == 1)
        #expect(snapshot.inputSent == 0)
        #expect(snapshot.pendingInputCount == 0)
        #expect(snapshot.inputQueueWait.sampleCount == 1)
        #expect(snapshot.inputSendDuration.sampleCount == 1)
        #expect(snapshot.sendFailures == 1)
    }

    @Test("old pending input cannot pollute a new diagnostics epoch")
    func oldPendingInputDoesNotPolluteNewEpoch() async {
        let diagnostics = SpiceClientDiagnosticsCollector(enabled: true)
        let recorder = InputRecorder()
        let pump = OrderedSpiceInputPump(
            send: { await recorder.append($0) },
            diagnostics: diagnostics,
            onFailure: { _ in Issue.record("unexpected send failure") }
        )

        pump.submit(.mouseMotion(dx: 2, dy: 3))
        diagnostics.setEnabled(false)
        diagnostics.reset()
        diagnostics.setEnabled(true)
        pump.submit(.mouseMotion(dx: 5, dy: -1))
        await pump.waitUntilIdle()

        let inputs = await recorder.inputs
        #expect(inputs.count == 1)
        if let first = inputs.first, case .mouseMotion(dx: 7, dy: 2) = first {
        } else {
            Issue.record("motion was not coalesced across the epoch boundary")
        }

        let snapshot = diagnostics.snapshot()
        #expect(snapshot.inputSubmitted == 1)
        #expect(snapshot.inputSent == 1)
        #expect(snapshot.inputCoalesced == 1)
        #expect(snapshot.motionSubmitted == 1)
        #expect(snapshot.motionSent == 1)
        #expect(snapshot.pendingInputCount == 0)
        #expect(snapshot.maximumPendingInputCount == 1)
        #expect(snapshot.inputQueueWait.sampleCount == 1)
        #expect(snapshot.inputSendDuration.sampleCount == 1)
        #expect(snapshot.sendFailures == 0)
    }

    @Test("send completion cannot pollute a new diagnostics epoch")
    func oldSendCompletionDoesNotPolluteNewEpoch() async {
        let diagnostics = SpiceClientDiagnosticsCollector(enabled: true)
        let sender = ControlledInputSender()
        let pump = OrderedSpiceInputPump(
            send: { await sender.send($0) },
            diagnostics: diagnostics,
            onFailure: { _ in Issue.record("unexpected send failure") }
        )

        pump.submit(.keyDown(scanCode: 0x1d))
        await sender.waitUntilStarted()
        diagnostics.setEnabled(false)
        diagnostics.reset()
        diagnostics.setEnabled(true)
        await sender.release()
        await pump.waitUntilIdle()

        let snapshot = diagnostics.snapshot()
        #expect(snapshot.isEnabled)
        #expect(snapshot.inputSubmitted == 0)
        #expect(snapshot.inputSent == 0)
        #expect(snapshot.inputCoalesced == 0)
        #expect(snapshot.pendingInputCount == 0)
        #expect(snapshot.maximumPendingInputCount == 0)
        #expect(snapshot.inputQueueWait == .empty)
        #expect(snapshot.inputSendDuration == .empty)
        #expect(snapshot.sendFailures == 0)
    }
}
