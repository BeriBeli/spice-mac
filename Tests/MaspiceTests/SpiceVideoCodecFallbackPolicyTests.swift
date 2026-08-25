// SPDX-License-Identifier: MIT
import Testing
@testable import SpiceController
import SwiftSpice
import VVConfig

private actor EstablishmentCompletionGate {
    private var entered = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var enteredContinuations: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        entered = true
        let continuations = enteredContinuations
        enteredContinuations.removeAll(keepingCapacity: false)
        for continuation in continuations { continuation.resume() }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { continuation in
            enteredContinuations.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@Suite("Video codec fallback policy")
struct SpiceVideoCodecFallbackPolicyTests {
    @MainActor
    @Test func `Only an idle client may start its one session`() {
        #expect(SpiceClient.canStartConnection(status: .idle, hasConnectionTask: false))
        #expect(!SpiceClient.canStartConnection(status: .idle, hasConnectionTask: true))
        #expect(!SpiceClient.canStartConnection(
            status: .disconnected,
            hasConnectionTask: false
        ))
        #expect(!SpiceClient.canStartConnection(
            status: .failed("terminal"),
            hasConnectionTask: false
        ))
    }

    @MainActor
    @Test func `Upstream diagnostics wait for the current session reset`() {
        #expect(SpiceClient.canRecordUpstreamDiagnostics(
            sampledGeneration: 4,
            currentGeneration: 4,
            readyGeneration: 4
        ))
        #expect(!SpiceClient.canRecordUpstreamDiagnostics(
            sampledGeneration: 4,
            currentGeneration: 4,
            readyGeneration: nil
        ))
        #expect(!SpiceClient.canRecordUpstreamDiagnostics(
            sampledGeneration: 4,
            currentGeneration: 5,
            readyGeneration: 4
        ))
        #expect(!SpiceClient.canRecordUpstreamDiagnostics(
            sampledGeneration: 4,
            currentGeneration: 4,
            readyGeneration: 3
        ))
    }

    @MainActor
    @Test func `Terminal failure invalidates the suspended connection attempt`() async {
        let client = SpiceClient(parameters: SpiceConnectionParameters(
            host: "example.invalid",
            port: 5_900
        ))
        let gate = EstablishmentCompletionGate()
        let lateEstablishment = Task { @MainActor in
            await gate.suspend()
            client.completeEstablishmentForTesting(generation: 0)
        }
        await gate.waitUntilEntered()

        client.fail("terminal", generation: 0)
        #expect(client.status == .failed("terminal"))

        // Resume the same completion primitive used by establish() after its
        // audio or Agent startup await. The captured epoch must not publish.
        await gate.release()
        await lateEstablishment.value
        #expect(client.status == .failed("terminal"))
    }

    @Test func `Hardware incompatibility reconnects to MJPEG only once per user connection`() {
        var policy = SpiceVideoCodecFallbackPolicy()
        let incompatibility = SpiceError.videoCodecUnavailable(
            SpiceVideoCodecFailure(
                codec: .h264,
                reason: .hardwareUnavailable(status: nil)
            )
        )

        let firstAttempt = policy.shouldReconnect(
            after: incompatibility,
            hasPresentedAdvancedVideo: false
        )
        let duplicateAttempt = policy.shouldReconnect(
            after: incompatibility,
            hasPresentedAdvancedVideo: false
        )
        let unrelatedAttempt = policy.shouldReconnect(
            after: .protocolError("unrelated"),
            hasPresentedAdvancedVideo: false
        )
        #expect(firstAttempt)
        #expect(!duplicateAttempt)
        #expect(!unrelatedAttempt)

        policy.reset()
        let attemptAfterReset = policy.shouldReconnect(
            after: incompatibility,
            hasPresentedAdvancedVideo: false
        )
        #expect(attemptAfterReset)
    }

    @Test func `Ordinary transport and protocol failures never trigger codec reconnect`() {
        var policy = SpiceVideoCodecFallbackPolicy()

        let connectionAttempt = policy.shouldReconnect(
            after: .connectionFailed("offline"),
            hasPresentedAdvancedVideo: false
        )
        let protocolAttempt = policy.shouldReconnect(
            after: .protocolError("bad packet"),
            hasPresentedAdvancedVideo: false
        )
        #expect(!connectionAttempt)
        #expect(!protocolAttempt)
        #expect(!policy.didReconnect)
    }

    @Test func `Explicit failed-attempt disconnect is suppressed once in retry generation`() {
        var policy = SpiceVideoCodecFallbackPolicy()
        let incompatibility = SpiceError.videoCodecUnavailable(
            SpiceVideoCodecFailure(
                codec: .h264,
                reason: .hardwareUnavailable(status: nil)
            )
        )

        let shouldReconnect = policy.shouldReconnect(
            after: incompatibility,
            hasPresentedAdvancedVideo: false
        )
        #expect(shouldReconnect)
        policy.expectFailedAttemptDisconnect(generation: 8)

        let wrongAttempt = policy.consumeExpectedDisconnect(generation: 7)
        #expect(!wrongAttempt)
        let expectedGeneration = policy.consumeExpectedDisconnect(generation: 8)
        let duplicate = policy.consumeExpectedDisconnect(generation: 8)
        #expect(expectedGeneration)
        #expect(!duplicate)
    }

    @Test func `Cancelling retry cannot suppress a later disconnect`() {
        var policy = SpiceVideoCodecFallbackPolicy()
        policy.expectFailedAttemptDisconnect(generation: 8)
        policy.cancelExpectedDisconnect()

        let laterDisconnect = policy.consumeExpectedDisconnect(generation: 8)
        #expect(!laterDisconnect)
    }

    @Test func `A presented hardware video stream is never replaced mid-session`() {
        var policy = SpiceVideoCodecFallbackPolicy()
        let unsupportedProfile = SpiceError.videoCodecUnavailable(
            SpiceVideoCodecFailure(
                codec: .h264,
                reason: .unsupportedFormat(status: -12_950)
            )
        )

        let attempt = policy.shouldReconnect(
            after: unsupportedProfile,
            hasPresentedAdvancedVideo: true
        )
        #expect(!attempt)
        #expect(!policy.didReconnect)
    }
}
