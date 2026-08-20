// SPDX-License-Identifier: MIT
import Foundation
import SwiftSpice

public struct SpiceLatencySummary: Sendable, Equatable {
    public let sampleCount: UInt64
    public let p95Milliseconds: Double?
    public let maximumMilliseconds: Double?

    public init(
        sampleCount: UInt64,
        p95Milliseconds: Double?,
        maximumMilliseconds: Double?
    ) {
        self.sampleCount = sampleCount
        self.p95Milliseconds = p95Milliseconds
        self.maximumMilliseconds = maximumMilliseconds
    }

    public static let empty = SpiceLatencySummary(
        sampleCount: 0,
        p95Milliseconds: nil,
        maximumMilliseconds: nil
    )
}

public struct SpiceClientSwiftSpiceDiagnostics: Sendable, Equatable {
    public let baseline: SpiceSessionDiagnostics
    public let latest: SpiceSessionDiagnostics
    public let latestSampleAgeMilliseconds: Double

    public init(
        baseline: SpiceSessionDiagnostics,
        latest: SpiceSessionDiagnostics,
        latestSampleAgeMilliseconds: Double = 0
    ) {
        self.baseline = baseline
        self.latest = latest
        self.latestSampleAgeMilliseconds = latestSampleAgeMilliseconds
    }
}

public enum SpiceClientClipboardDiagnosticsState: String, Sendable, Equatable {
    case unknown
    case disabled
    case waitingForCapabilities = "waiting_for_capabilities"
    case ready
    case unavailable
    case failed
}

/// Aggregate, content-free observations from the session VDAgent path.
public struct SpiceClientAgentDiagnostics: Sendable, Equatable {
    public internal(set) var supportObserved: Bool
    public internal(set) var agentConnected: Bool
    public internal(set) var capabilityAnnouncementReceived: Bool
    public internal(set) var monitorConfigurationSupported: Bool
    public internal(set) var clipboardState: SpiceClientClipboardDiagnosticsState
    public internal(set) var agentConnectTransitions: UInt64
    public internal(set) var agentDisconnectTransitions: UInt64
    public internal(set) var agentManagerStartFailures: UInt64
    public internal(set) var capabilityAnnouncementsAttempted: UInt64
    public internal(set) var capabilityAnnouncementsSent: UInt64
    public internal(set) var capabilityAnnouncementFailures: UInt64
    public internal(set) var inboundMessages: UInt64
    public internal(set) var inboundCurrentProtocolMessages: UInt64
    public internal(set) var inboundUnexpectedProtocolMessages: UInt64
    public internal(set) var inboundCapabilityAnnouncements: UInt64
    public internal(set) var inboundClipboardMessages: UInt64
    public internal(set) var inboundClipboardDataMessages: UInt64
    public internal(set) var inboundClipboardGrabMessages: UInt64
    public internal(set) var inboundClipboardRequestMessages: UInt64
    public internal(set) var inboundClipboardReleaseMessages: UInt64
    public internal(set) var inboundMonitorReplies: UInt64
    public internal(set) var inboundFileTransferMessages: UInt64
    public internal(set) var inboundOtherMessages: UInt64
    public internal(set) var inboundDecodeFailures: UInt64
    public internal(set) var peerLegacyClipboardCapability: Bool?
    public internal(set) var peerClipboardByDemandCapability: Bool?
    public internal(set) var managerClipboardFailures: UInt64
    public internal(set) var lastManagerClipboardFailureCategory:
        SpiceClipboardFailureCategory?
    public internal(set) var lastInboundProtocolID: UInt32?
    public internal(set) var lastInboundMessageType: UInt32?
    public internal(set) var clipboardReadyEvents: UInt64
    public internal(set) var clipboardUnavailableEvents: UInt64
    public internal(set) var clipboardLocalTextOfferEvents: UInt64
    public internal(set) var clipboardGuestTextEvents: UInt64
    public internal(set) var clipboardOversizedLocalTextEvents: UInt64
    public internal(set) var clipboardFailures: UInt64
    public internal(set) var monitorConfigurationRequests: UInt64
    public internal(set) var monitorConfigurationBlocked: UInt64
    public internal(set) var monitorConfigurationQueued: UInt64
    public internal(set) var monitorConfigurationSent: UInt64
    public internal(set) var monitorConfigurationAcknowledged: UInt64
    public internal(set) var monitorConfigurationRejected: UInt64
    public internal(set) var monitorConfigurationUnsupported: UInt64
    public internal(set) var monitorConfigurationFailures: UInt64
    public internal(set) var monitorConfigurationProtocolFailures: UInt64

    public init(
        supportObserved: Bool = false,
        agentConnected: Bool = false,
        capabilityAnnouncementReceived: Bool = false,
        monitorConfigurationSupported: Bool = false,
        clipboardState: SpiceClientClipboardDiagnosticsState = .unknown,
        agentConnectTransitions: UInt64 = 0,
        agentDisconnectTransitions: UInt64 = 0,
        agentManagerStartFailures: UInt64 = 0,
        capabilityAnnouncementsAttempted: UInt64 = 0,
        capabilityAnnouncementsSent: UInt64 = 0,
        capabilityAnnouncementFailures: UInt64 = 0,
        inboundMessages: UInt64 = 0,
        inboundCurrentProtocolMessages: UInt64 = 0,
        inboundUnexpectedProtocolMessages: UInt64 = 0,
        inboundCapabilityAnnouncements: UInt64 = 0,
        inboundClipboardMessages: UInt64 = 0,
        inboundClipboardDataMessages: UInt64 = 0,
        inboundClipboardGrabMessages: UInt64 = 0,
        inboundClipboardRequestMessages: UInt64 = 0,
        inboundClipboardReleaseMessages: UInt64 = 0,
        inboundMonitorReplies: UInt64 = 0,
        inboundFileTransferMessages: UInt64 = 0,
        inboundOtherMessages: UInt64 = 0,
        inboundDecodeFailures: UInt64 = 0,
        peerLegacyClipboardCapability: Bool? = nil,
        peerClipboardByDemandCapability: Bool? = nil,
        managerClipboardFailures: UInt64 = 0,
        lastManagerClipboardFailureCategory: SpiceClipboardFailureCategory? = nil,
        lastInboundProtocolID: UInt32? = nil,
        lastInboundMessageType: UInt32? = nil,
        clipboardReadyEvents: UInt64 = 0,
        clipboardUnavailableEvents: UInt64 = 0,
        clipboardLocalTextOfferEvents: UInt64 = 0,
        clipboardGuestTextEvents: UInt64 = 0,
        clipboardOversizedLocalTextEvents: UInt64 = 0,
        clipboardFailures: UInt64 = 0,
        monitorConfigurationRequests: UInt64 = 0,
        monitorConfigurationBlocked: UInt64 = 0,
        monitorConfigurationQueued: UInt64 = 0,
        monitorConfigurationSent: UInt64 = 0,
        monitorConfigurationAcknowledged: UInt64 = 0,
        monitorConfigurationRejected: UInt64 = 0,
        monitorConfigurationUnsupported: UInt64 = 0,
        monitorConfigurationFailures: UInt64 = 0,
        monitorConfigurationProtocolFailures: UInt64 = 0
    ) {
        self.supportObserved = supportObserved
        self.agentConnected = agentConnected
        self.capabilityAnnouncementReceived = capabilityAnnouncementReceived
        self.monitorConfigurationSupported = monitorConfigurationSupported
        self.clipboardState = clipboardState
        self.agentConnectTransitions = agentConnectTransitions
        self.agentDisconnectTransitions = agentDisconnectTransitions
        self.agentManagerStartFailures = agentManagerStartFailures
        self.capabilityAnnouncementsAttempted = capabilityAnnouncementsAttempted
        self.capabilityAnnouncementsSent = capabilityAnnouncementsSent
        self.capabilityAnnouncementFailures = capabilityAnnouncementFailures
        self.inboundMessages = inboundMessages
        self.inboundCurrentProtocolMessages = inboundCurrentProtocolMessages
        self.inboundUnexpectedProtocolMessages = inboundUnexpectedProtocolMessages
        self.inboundCapabilityAnnouncements = inboundCapabilityAnnouncements
        self.inboundClipboardMessages = inboundClipboardMessages
        self.inboundClipboardDataMessages = inboundClipboardDataMessages
        self.inboundClipboardGrabMessages = inboundClipboardGrabMessages
        self.inboundClipboardRequestMessages = inboundClipboardRequestMessages
        self.inboundClipboardReleaseMessages = inboundClipboardReleaseMessages
        self.inboundMonitorReplies = inboundMonitorReplies
        self.inboundFileTransferMessages = inboundFileTransferMessages
        self.inboundOtherMessages = inboundOtherMessages
        self.inboundDecodeFailures = inboundDecodeFailures
        self.peerLegacyClipboardCapability = peerLegacyClipboardCapability
        self.peerClipboardByDemandCapability = peerClipboardByDemandCapability
        self.managerClipboardFailures = managerClipboardFailures
        self.lastManagerClipboardFailureCategory = lastManagerClipboardFailureCategory
        self.lastInboundProtocolID = lastInboundProtocolID
        self.lastInboundMessageType = lastInboundMessageType
        self.clipboardReadyEvents = clipboardReadyEvents
        self.clipboardUnavailableEvents = clipboardUnavailableEvents
        self.clipboardLocalTextOfferEvents = clipboardLocalTextOfferEvents
        self.clipboardGuestTextEvents = clipboardGuestTextEvents
        self.clipboardOversizedLocalTextEvents = clipboardOversizedLocalTextEvents
        self.clipboardFailures = clipboardFailures
        self.monitorConfigurationRequests = monitorConfigurationRequests
        self.monitorConfigurationBlocked = monitorConfigurationBlocked
        self.monitorConfigurationQueued = monitorConfigurationQueued
        self.monitorConfigurationSent = monitorConfigurationSent
        self.monitorConfigurationAcknowledged = monitorConfigurationAcknowledged
        self.monitorConfigurationRejected = monitorConfigurationRejected
        self.monitorConfigurationUnsupported = monitorConfigurationUnsupported
        self.monitorConfigurationFailures = monitorConfigurationFailures
        self.monitorConfigurationProtocolFailures = monitorConfigurationProtocolFailures
    }

    public static let empty = SpiceClientAgentDiagnostics()
}

public struct SpiceClientDiagnosticsSnapshot: Sendable, Equatable {
    public let isEnabled: Bool
    public let inputSubmitted: UInt64
    public let inputSent: UInt64
    public let inputCoalesced: UInt64
    public let motionSubmitted: UInt64
    public let motionSent: UInt64
    public let mouseMotionAcknowledgements: UInt64
    public let pendingInputCount: Int
    public let maximumPendingInputCount: Int
    public let inputQueueWait: SpiceLatencySummary
    public let inputSendDuration: SpiceLatencySummary
    public let clientFrameEvents: UInt64
    public let clientFrameEventGap: SpiceLatencySummary
    public let mainActorSchedulingDelay: SpiceLatencySummary
    public let sendFailures: UInt64
    public let desktopViewUpdates: UInt64
    public let clientFramesSupersededBeforeDesktopView: UInt64
    public let clientToDesktopViewUpdate: SpiceLatencySummary
    public let agent: SpiceClientAgentDiagnostics
    public let swiftSpiceDiagnostics: SpiceClientSwiftSpiceDiagnostics?

    public init(
        isEnabled: Bool,
        inputSubmitted: UInt64,
        inputSent: UInt64,
        inputCoalesced: UInt64,
        motionSubmitted: UInt64,
        motionSent: UInt64,
        mouseMotionAcknowledgements: UInt64,
        pendingInputCount: Int,
        maximumPendingInputCount: Int,
        inputQueueWait: SpiceLatencySummary,
        inputSendDuration: SpiceLatencySummary,
        clientFrameEvents: UInt64,
        clientFrameEventGap: SpiceLatencySummary,
        mainActorSchedulingDelay: SpiceLatencySummary,
        sendFailures: UInt64,
        desktopViewUpdates: UInt64 = 0,
        clientFramesSupersededBeforeDesktopView: UInt64 = 0,
        clientToDesktopViewUpdate: SpiceLatencySummary = .empty,
        agent: SpiceClientAgentDiagnostics = .empty,
        swiftSpiceDiagnostics: SpiceClientSwiftSpiceDiagnostics? = nil
    ) {
        self.isEnabled = isEnabled
        self.inputSubmitted = inputSubmitted
        self.inputSent = inputSent
        self.inputCoalesced = inputCoalesced
        self.motionSubmitted = motionSubmitted
        self.motionSent = motionSent
        self.mouseMotionAcknowledgements = mouseMotionAcknowledgements
        self.pendingInputCount = pendingInputCount
        self.maximumPendingInputCount = maximumPendingInputCount
        self.inputQueueWait = inputQueueWait
        self.inputSendDuration = inputSendDuration
        self.clientFrameEvents = clientFrameEvents
        self.clientFrameEventGap = clientFrameEventGap
        self.mainActorSchedulingDelay = mainActorSchedulingDelay
        self.sendFailures = sendFailures
        self.desktopViewUpdates = desktopViewUpdates
        self.clientFramesSupersededBeforeDesktopView =
            clientFramesSupersededBeforeDesktopView
        self.clientToDesktopViewUpdate = clientToDesktopViewUpdate
        self.agent = agent
        self.swiftSpiceDiagnostics = swiftSpiceDiagnostics
    }

    public static let disabled = SpiceClientDiagnosticsSnapshot(
        isEnabled: false,
        inputSubmitted: 0,
        inputSent: 0,
        inputCoalesced: 0,
        motionSubmitted: 0,
        motionSent: 0,
        mouseMotionAcknowledgements: 0,
        pendingInputCount: 0,
        maximumPendingInputCount: 0,
        inputQueueWait: .empty,
        inputSendDuration: .empty,
        clientFrameEvents: 0,
        clientFrameEventGap: .empty,
        mainActorSchedulingDelay: .empty,
        sendFailures: 0,
        agent: .empty,
        swiftSpiceDiagnostics: nil
    )
}

@MainActor
final class SpiceClientDiagnosticsCollector {
    struct MeasurementToken: Sendable, Hashable {
        fileprivate let generation: UInt64
    }

    private struct Metrics {
        var inputSubmitted: UInt64 = 0
        var inputSent: UInt64 = 0
        var inputCoalesced: UInt64 = 0
        var motionSubmitted: UInt64 = 0
        var motionSent: UInt64 = 0
        var mouseMotionAcknowledgements: UInt64 = 0
        var pendingInputCount = 0
        var maximumPendingInputCount = 0
        var inputQueueWait = FixedLatencyHistogram()
        var inputSendDuration = FixedLatencyHistogram()
        var clientFrameEvents: UInt64 = 0
        var clientFrameEventGap = FixedLatencyHistogram()
        var desktopViewUpdates: UInt64 = 0
        var clientFramesSupersededBeforeDesktopView: UInt64 = 0
        var clientToDesktopViewUpdate = FixedLatencyHistogram()
        var mainActorSchedulingDelay = FixedLatencyHistogram()
        var sendFailures: UInt64 = 0
        var agent: SpiceClientAgentDiagnostics = .empty
        var previousAgentConnected: Bool?
        var previousFrameInstant: ContinuousClock.Instant?
        var latestFrameSequence: UInt64?
        var latestFrameInstant: ContinuousClock.Instant?
        var firstObservedFrameSequence: UInt64?
        var previousDesktopViewSequence: UInt64?
        var swiftSpiceDiagnostics: SpiceClientSwiftSpiceDiagnostics?
        var swiftSpiceLatestSampleInstant: ContinuousClock.Instant?
    }

    private var enabled: Bool
    private var measurementGeneration: UInt64
    private var metrics = Metrics()

    var isEnabled: Bool { enabled }
    var currentMeasurementToken: MeasurementToken? {
        enabled ? MeasurementToken(generation: measurementGeneration) : nil
    }

    init(enabled: Bool = false) {
        self.enabled = enabled
        measurementGeneration = enabled ? 1 : 0
    }

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        measurementGeneration &+= 1
        self.enabled = enabled
        metrics.previousFrameInstant = nil
        metrics.latestFrameSequence = nil
        metrics.latestFrameInstant = nil
        metrics.firstObservedFrameSequence = nil
        metrics.previousDesktopViewSequence = nil
    }

    func reset() {
        measurementGeneration &+= 1
        metrics = Metrics()
    }

    func isCurrentMeasurement(_ token: MeasurementToken?) -> Bool {
        guard enabled, let token else { return false }
        return token.generation == measurementGeneration
    }

    func snapshot() -> SpiceClientDiagnosticsSnapshot {
        snapshot(at: ContinuousClock().now)
    }

    func snapshot(at instant: ContinuousClock.Instant) -> SpiceClientDiagnosticsSnapshot {
        let swiftSpiceDiagnostics = metrics.swiftSpiceDiagnostics.map { current in
            let age = metrics.swiftSpiceLatestSampleInstant.map {
                diagnosticsMilliseconds($0.duration(to: instant))
            } ?? 0
            return SpiceClientSwiftSpiceDiagnostics(
                baseline: current.baseline,
                latest: current.latest,
                latestSampleAgeMilliseconds: age
            )
        }
        return SpiceClientDiagnosticsSnapshot(
            isEnabled: enabled,
            inputSubmitted: metrics.inputSubmitted,
            inputSent: metrics.inputSent,
            inputCoalesced: metrics.inputCoalesced,
            motionSubmitted: metrics.motionSubmitted,
            motionSent: metrics.motionSent,
            mouseMotionAcknowledgements: metrics.mouseMotionAcknowledgements,
            pendingInputCount: metrics.pendingInputCount,
            maximumPendingInputCount: metrics.maximumPendingInputCount,
            inputQueueWait: metrics.inputQueueWait.summary,
            inputSendDuration: metrics.inputSendDuration.summary,
            clientFrameEvents: metrics.clientFrameEvents,
            clientFrameEventGap: metrics.clientFrameEventGap.summary,
            mainActorSchedulingDelay: metrics.mainActorSchedulingDelay.summary,
            sendFailures: metrics.sendFailures,
            desktopViewUpdates: metrics.desktopViewUpdates,
            clientFramesSupersededBeforeDesktopView:
                metrics.clientFramesSupersededBeforeDesktopView,
            clientToDesktopViewUpdate: metrics.clientToDesktopViewUpdate.summary,
            agent: metrics.agent,
            swiftSpiceDiagnostics: swiftSpiceDiagnostics
        )
    }

    func recordInputSubmitted(isMotion: Bool) -> MeasurementToken? {
        guard let token = currentMeasurementToken else { return nil }
        metrics.inputSubmitted &+= 1
        if isMotion { metrics.motionSubmitted &+= 1 }
        return token
    }

    func recordInputCoalesced(token: MeasurementToken?) {
        guard isCurrentMeasurement(token) else { return }
        metrics.inputCoalesced &+= 1
    }

    func recordPendingInputCount(_ count: Int, token: MeasurementToken?) {
        guard isCurrentMeasurement(token) else { return }
        let count = max(0, count)
        metrics.pendingInputCount = count
        metrics.maximumPendingInputCount = max(metrics.maximumPendingInputCount, count)
    }

    func recordInputDequeued(queueWait: Duration, token: MeasurementToken?) {
        guard isCurrentMeasurement(token) else { return }
        metrics.inputQueueWait.record(queueWait)
    }

    func recordInputSent(
        isMotion: Bool,
        sendDuration: Duration,
        token: MeasurementToken?
    ) {
        guard isCurrentMeasurement(token) else { return }
        metrics.inputSent &+= 1
        if isMotion { metrics.motionSent &+= 1 }
        metrics.inputSendDuration.record(sendDuration)
    }

    func recordSendFailure(sendDuration: Duration, token: MeasurementToken?) {
        guard isCurrentMeasurement(token) else { return }
        metrics.inputSendDuration.record(sendDuration)
        metrics.sendFailures &+= 1
    }

    func recordClientFrameEvent(sequence: UInt64) {
        guard enabled else { return }
        recordClientFrameEvent(
            sequence: sequence,
            at: ContinuousClock().now
        )
    }

    func recordClientFrameEvent(
        sequence: UInt64 = 0,
        at instant: ContinuousClock.Instant
    ) {
        guard enabled else { return }
        metrics.clientFrameEvents &+= 1
        if let previous = metrics.previousFrameInstant {
            metrics.clientFrameEventGap.record(previous.duration(to: instant))
        }
        metrics.previousFrameInstant = instant
        if metrics.firstObservedFrameSequence == nil {
            metrics.firstObservedFrameSequence = sequence
        }
        metrics.latestFrameSequence = sequence
        metrics.latestFrameInstant = instant
    }

    func recordDesktopViewUpdate(
        sequence: UInt64,
        at instant: ContinuousClock.Instant = ContinuousClock().now
    ) {
        guard enabled,
              metrics.latestFrameSequence == sequence,
              let frameInstant = metrics.latestFrameInstant,
              metrics.previousDesktopViewSequence != sequence
        else { return }
        metrics.desktopViewUpdates &+= 1
        if let previous = metrics.previousDesktopViewSequence {
            if sequence > previous {
                metrics.clientFramesSupersededBeforeDesktopView &+= sequence - previous - 1
            }
        } else if let first = metrics.firstObservedFrameSequence,
                  sequence >= first {
            metrics.clientFramesSupersededBeforeDesktopView &+= sequence - first
        }
        metrics.previousDesktopViewSequence = sequence
        metrics.clientToDesktopViewUpdate.record(frameInstant.duration(to: instant))
    }

    func recordMouseMotionAcknowledged() {
        guard enabled else { return }
        metrics.mouseMotionAcknowledgements &+= 1
    }

    func recordMainActorSchedulingDelay(_ duration: Duration) {
        guard enabled else { return }
        metrics.mainActorSchedulingDelay.record(duration)
    }

    func recordAgentSupport(
        _ support: SpiceDisplayConfigurationSupport,
        countTransition: Bool = true
    ) {
        guard enabled else { return }
        if countTransition,
           let previous = metrics.previousAgentConnected,
           previous != support.agentConnected {
            if support.agentConnected {
                metrics.agent.agentConnectTransitions &+= 1
            } else {
                metrics.agent.agentDisconnectTransitions &+= 1
            }
        }
        metrics.previousAgentConnected = support.agentConnected
        metrics.agent.supportObserved = true
        metrics.agent.agentConnected = support.agentConnected
        metrics.agent.capabilityAnnouncementReceived =
            support.hasExplicitPeerCapabilities
        metrics.agent.monitorConfigurationSupported =
            support.agentConnected && support.supportsMonitorConfiguration
        if !support.agentConnected,
           metrics.agent.clipboardState != .disabled {
            metrics.agent.clipboardState = .unavailable
        } else if support.agentConnected,
                  metrics.agent.clipboardState == .unknown {
            metrics.agent.clipboardState = .waitingForCapabilities
        }
    }

    func seedAgentState(
        support: SpiceDisplayConfigurationSupport?,
        clipboardState: SpiceClientClipboardDiagnosticsState
    ) {
        guard enabled else { return }
        if let support {
            recordAgentSupport(support, countTransition: false)
        }
        metrics.agent.clipboardState = clipboardState
    }

    func recordAgentManagerStartFailure() {
        guard enabled else { return }
        metrics.agent.agentManagerStartFailures &+= 1
    }

    func recordAgentWireDiagnostics(_ diagnostics: SpiceAgentWireDiagnostics) {
        guard enabled else { return }
        metrics.agent.capabilityAnnouncementsAttempted =
            diagnostics.capabilityAnnouncementsAttempted
        metrics.agent.capabilityAnnouncementsSent = diagnostics.capabilityAnnouncementsSent
        metrics.agent.capabilityAnnouncementFailures =
            diagnostics.capabilityAnnouncementFailures
        metrics.agent.inboundMessages = diagnostics.inboundMessages
        metrics.agent.inboundCurrentProtocolMessages =
            diagnostics.inboundCurrentProtocolMessages
        metrics.agent.inboundUnexpectedProtocolMessages =
            diagnostics.inboundUnexpectedProtocolMessages
        metrics.agent.inboundCapabilityAnnouncements =
            diagnostics.inboundCapabilityAnnouncements
        metrics.agent.inboundClipboardMessages = diagnostics.inboundClipboardMessages
        metrics.agent.inboundClipboardDataMessages =
            diagnostics.inboundClipboardDataMessages
        metrics.agent.inboundClipboardGrabMessages =
            diagnostics.inboundClipboardGrabMessages
        metrics.agent.inboundClipboardRequestMessages =
            diagnostics.inboundClipboardRequestMessages
        metrics.agent.inboundClipboardReleaseMessages =
            diagnostics.inboundClipboardReleaseMessages
        metrics.agent.inboundMonitorReplies = diagnostics.inboundMonitorReplies
        metrics.agent.inboundFileTransferMessages = diagnostics.inboundFileTransferMessages
        metrics.agent.inboundOtherMessages = diagnostics.inboundOtherMessages
        metrics.agent.inboundDecodeFailures = diagnostics.inboundDecodeFailures
        metrics.agent.peerLegacyClipboardCapability =
            diagnostics.peerLegacyClipboardCapability
        metrics.agent.peerClipboardByDemandCapability =
            diagnostics.peerClipboardByDemandCapability
        metrics.agent.managerClipboardFailures = diagnostics.clipboardFailures
        metrics.agent.lastManagerClipboardFailureCategory =
            diagnostics.lastClipboardFailureCategory
        metrics.agent.lastInboundProtocolID = diagnostics.lastInboundProtocolID
        metrics.agent.lastInboundMessageType = diagnostics.lastInboundMessageType
    }

    func recordClipboardEvent(_ event: SpiceClipboardEvent) {
        guard enabled else { return }
        switch event {
        case .ready:
            metrics.agent.clipboardState = .ready
            metrics.agent.clipboardReadyEvents &+= 1
        case .unavailable:
            metrics.agent.clipboardState = .unavailable
            metrics.agent.clipboardUnavailableEvents &+= 1
        case .guestText:
            metrics.agent.clipboardGuestTextEvents &+= 1
        case .localTextOffered:
            metrics.agent.clipboardLocalTextOfferEvents &+= 1
        case .oversizedLocalText:
            metrics.agent.clipboardOversizedLocalTextEvents &+= 1
        case .failed:
            metrics.agent.clipboardState = .failed
            metrics.agent.clipboardFailures &+= 1
        }
    }

    func recordDisplayConfigurationEvent(_ event: SpiceDisplayConfigurationEvent) {
        guard enabled else { return }
        switch event {
        case .queued:
            metrics.agent.monitorConfigurationQueued &+= 1
        case .sent:
            metrics.agent.monitorConfigurationSent &+= 1
        case .acknowledged:
            metrics.agent.monitorConfigurationAcknowledged &+= 1
        case .rejected:
            metrics.agent.monitorConfigurationRejected &+= 1
        case .unsupported:
            metrics.agent.monitorConfigurationUnsupported &+= 1
        case .failed:
            metrics.agent.monitorConfigurationFailures &+= 1
        case .protocolFailure:
            metrics.agent.monitorConfigurationProtocolFailures &+= 1
        }
    }

    func recordMonitorConfigurationRequest(blocked: Bool) {
        guard enabled else { return }
        metrics.agent.monitorConfigurationRequests &+= 1
        if blocked {
            metrics.agent.monitorConfigurationBlocked &+= 1
        }
    }

    func recordSwiftSpiceDiagnostics(
        _ diagnostics: SpiceSessionDiagnostics,
        sampledAt instant: ContinuousClock.Instant? = nil
    ) {
        guard enabled else { return }
        metrics.swiftSpiceLatestSampleInstant = instant ?? ContinuousClock().now
        if let current = metrics.swiftSpiceDiagnostics {
            metrics.swiftSpiceDiagnostics = SpiceClientSwiftSpiceDiagnostics(
                baseline: current.baseline,
                latest: diagnostics
            )
        } else {
            // The upstream baseline may arrive after diagnostics were enabled,
            // especially when the HUD is opened while connecting. Rebase the
            // downstream frame-event metrics here so the display-pipeline
            // counters share the same best-effort epoch.
            metrics.clientFrameEvents = 0
            metrics.clientFrameEventGap = FixedLatencyHistogram()
            metrics.previousFrameInstant = nil
            metrics.swiftSpiceDiagnostics = SpiceClientSwiftSpiceDiagnostics(
                baseline: diagnostics,
                latest: diagnostics
            )
        }
    }
}

private struct FixedLatencyHistogram {
    // The final bucket holds values above the largest listed upper bound.
    private static let upperBoundsMilliseconds: [Double] = [
        0, 0.125, 0.25, 0.5, 1, 2, 4, 8, 16, 33, 50, 100, 250, 500, 1_000,
        2_000, 5_000,
    ]

    private var buckets = Array(
        repeating: UInt64(0),
        count: Self.upperBoundsMilliseconds.count + 1
    )
    private var sampleCount: UInt64 = 0
    private var maximumMilliseconds: Double?

    mutating func record(_ duration: Duration) {
        let milliseconds = diagnosticsMilliseconds(duration)
        let index = Self.upperBoundsMilliseconds.firstIndex { milliseconds <= $0 }
            ?? Self.upperBoundsMilliseconds.count
        buckets[index] &+= 1
        sampleCount &+= 1
        maximumMilliseconds = max(maximumMilliseconds ?? milliseconds, milliseconds)
    }

    var summary: SpiceLatencySummary {
        guard sampleCount > 0, let maximumMilliseconds else { return .empty }
        let rank = UInt64((Double(sampleCount) * 0.95).rounded(.up))
        var accumulated: UInt64 = 0
        for (index, count) in buckets.enumerated() {
            accumulated &+= count
            guard accumulated >= rank else { continue }
            let p95 = index < Self.upperBoundsMilliseconds.count
                ? min(Self.upperBoundsMilliseconds[index], maximumMilliseconds)
                : maximumMilliseconds
            return SpiceLatencySummary(
                sampleCount: sampleCount,
                p95Milliseconds: p95,
                maximumMilliseconds: maximumMilliseconds
            )
        }
        return SpiceLatencySummary(
            sampleCount: sampleCount,
            p95Milliseconds: maximumMilliseconds,
            maximumMilliseconds: maximumMilliseconds
        )
    }

}

private func diagnosticsMilliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    let value = Double(components.seconds) * 1_000
        + Double(components.attoseconds) / 1_000_000_000_000_000
    return max(0, value.isFinite ? value : 0)
}
