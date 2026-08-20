// SPDX-License-Identifier: MIT
import SpiceController
import SwiftUI

struct SessionDiagnosticsHeader: View {
    let isCollecting: Bool

    var body: some View {
        HStack {
            Label("Session Diagnostics", systemImage: "waveform.path.ecg")
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Group {
                if isCollecting {
                    Text("Live")
                } else {
                    Text("Stopped")
                }
            }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isCollecting ? Color.green : Color.secondary)
        }
    }
}

struct SessionDiagnosticsInputSection: View {
    let pendingCount: String
    let maximumPendingCount: String
    let queueWait: SpiceLatencySummary
    let sendDuration: SpiceLatencySummary
    let submitted: String
    let sent: String
    let coalesced: String
    let motionSent: String
    let motionAcknowledgements: String
    let sendFailures: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            SessionDiagnosticsSectionHeader(title: "Input")
            SessionDiagnosticsMetricRow(
                label: "Input queue current / max",
                value: "\(pendingCount) / \(maximumPendingCount)"
            )
            SessionDiagnosticsLatencyRow(label: "Queue wait p95 / max", latency: queueWait)
            SessionDiagnosticsLatencyRow(label: "Send p95 / max", latency: sendDuration)
            SessionDiagnosticsMetricRow(
                label: "Submitted / sent / coalesced",
                value: "\(submitted) / \(sent) / \(coalesced)"
            )
            SessionDiagnosticsMetricRow(
                label: "Motion sent / ACK",
                value: "\(motionSent) / \(motionAcknowledgements)"
            )
            SessionDiagnosticsMetricRow(label: "Send failures", value: "\(sendFailures)")
        }
    }
}

struct SessionDiagnosticsAgentSection: View {
    let metrics: SpiceClientAgentDiagnostics

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            SessionDiagnosticsSectionHeader(title: "VDAgent")
            SessionDiagnosticsMetricRow(
                label: "Connection / capabilities",
                value: "\(connectionState) / \(capabilityState)"
            )
            SessionDiagnosticsMetricRow(
                label: "Capability request try / sent / fail",
                value: "\(metrics.capabilityAnnouncementsAttempted) / "
                    + "\(metrics.capabilityAnnouncementsSent) / "
                    + "\(metrics.capabilityAnnouncementFailures)"
            )
            SessionDiagnosticsMetricRow(
                label: "Inbound total / capabilities / decode fail",
                value: "\(metrics.inboundMessages) / "
                    + "\(metrics.inboundCapabilityAnnouncements) / "
                    + "\(metrics.inboundDecodeFailures)"
            )
            SessionDiagnosticsMetricRow(
                label: "Last protocol / type / unexpected protocol",
                value: "\(diagnosticValue(metrics.lastInboundProtocolID)) / "
                    + "\(diagnosticValue(metrics.lastInboundMessageType)) / "
                    + "\(metrics.inboundUnexpectedProtocolMessages)"
            )
            SessionDiagnosticsMetricRow(
                label: "Clipboard data / grab / request / release",
                value: "\(metrics.inboundClipboardDataMessages) / "
                    + "\(metrics.inboundClipboardGrabMessages) / "
                    + "\(metrics.inboundClipboardRequestMessages) / "
                    + "\(metrics.inboundClipboardReleaseMessages)"
            )
            SessionDiagnosticsMetricRow(
                label: "Peer clipboard legacy / by-demand",
                value: "\(diagnosticValue(metrics.peerLegacyClipboardCapability)) / "
                    + "\(diagnosticValue(metrics.peerClipboardByDemandCapability))"
            )
            SessionDiagnosticsMetricRow(
                label: "Manager clipboard failures / last category",
                value: "\(metrics.managerClipboardFailures) / "
                    + "\(metrics.lastManagerClipboardFailureCategory?.rawValue ?? "—")"
            )
            SessionDiagnosticsMetricRow(
                label: "Clipboard / host offers / guest data",
                value: "\(clipboardState) / "
                    + "\(metrics.clipboardLocalTextOfferEvents) / "
                    + "\(metrics.clipboardGuestTextEvents)"
            )
            SessionDiagnosticsMetricRow(
                label: "Monitor supported / requests / blocked",
                value: "\(monitorSupportState) / "
                    + "\(metrics.monitorConfigurationRequests) / "
                    + "\(metrics.monitorConfigurationBlocked)"
            )
            SessionDiagnosticsMetricRow(
                label: "Monitor sent / ACK / errors",
                value: "\(metrics.monitorConfigurationSent) / "
                    + "\(metrics.monitorConfigurationAcknowledged) / "
                    + "\(monitorErrorCount)"
            )
            SessionDiagnosticsMetricRow(
                label: "Clipboard event / Agent start errors",
                value: "\(metrics.clipboardFailures) / "
                    + "\(metrics.agentManagerStartFailures)"
            )
        }
    }

    private var connectionState: String {
        guard metrics.supportObserved else { return "—" }
        return metrics.agentConnected ? "Connected" : "Unavailable"
    }

    private var capabilityState: String {
        guard metrics.supportObserved else { return "—" }
        if metrics.capabilityAnnouncementReceived { return "Received" }
        return metrics.agentConnected ? "Waiting" : "Unavailable"
    }

    private var monitorSupportState: String {
        guard metrics.supportObserved else { return "—" }
        return metrics.monitorConfigurationSupported ? "Yes" : "No"
    }

    private var clipboardState: String {
        switch metrics.clipboardState {
        case .unknown: "—"
        case .disabled: "Disabled"
        case .waitingForCapabilities: "Waiting"
        case .ready: "Ready"
        case .unavailable: "Unavailable"
        case .failed: "Failed"
        }
    }

    private var monitorErrorCount: UInt64 {
        metrics.monitorConfigurationRejected
            &+ metrics.monitorConfigurationUnsupported
            &+ metrics.monitorConfigurationFailures
            &+ metrics.monitorConfigurationProtocolFailures
    }
}

struct SessionDiagnosticsDisplaySection: View {
    let publisherSubmissions: UInt64?
    let publisherEmittedFrames: UInt64?
    let publisherStaleSnapshots: UInt64?
    let publisherPendingEvictions: UInt64?
    let publisherPendingSurfaces: Int?
    let publisherFramedReceiveBatchStartGap: SpiceLatencySummary?
    let publisherMessageReceiveToSurfaceReady: SpiceLatencySummary?
    let publisherSurfaceReadyToSubmit: SpiceLatencySummary?
    let mailboxFramesSent: UInt64?
    let mailboxFramesDelivered: UInt64?
    let mailboxFramesCoalesced: UInt64?
    let mailboxFramesEvicted: UInt64?
    let clientFrameEvents: String
    let clientFrameEventGap: SpiceLatencySummary
    let desktopViewUpdates: String
    let clientFramesSupersededBeforeDesktopView: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            SessionDiagnosticsSectionHeader(title: "Display pipeline")
            SessionDiagnosticsMetricRow(
                label: "Publisher submit / emit / client",
                value: "\(diagnosticValue(publisherSubmissions)) / "
                    + "\(diagnosticValue(publisherEmittedFrames)) / \(clientFrameEvents)"
            )
            SessionDiagnosticsMetricRow(
                label: "Publisher stale / evicted / pending sample",
                value: "\(diagnosticValue(publisherStaleSnapshots)) / "
                    + "\(diagnosticValue(publisherPendingEvictions)) / "
                    + "\(diagnosticValue(publisherPendingSurfaces))"
            )
            if let publisherFramedReceiveBatchStartGap,
               let publisherMessageReceiveToSurfaceReady,
               let publisherSurfaceReadyToSubmit {
                SessionDiagnosticsLatencyRow(
                    label: "Framed-receive batch gap p95 / max",
                    latency: publisherFramedReceiveBatchStartGap
                )
                SessionDiagnosticsLatencyRow(
                    label: "Receive → surface ready p95 / max",
                    latency: publisherMessageReceiveToSurfaceReady
                )
                SessionDiagnosticsLatencyRow(
                    label: "Surface ready → publisher p95 / max",
                    latency: publisherSurfaceReadyToSubmit
                )
            }
            SessionDiagnosticsMetricRow(
                label: "Mailbox sent / delivered / coalesced / evicted",
                value: "\(diagnosticValue(mailboxFramesSent)) / "
                    + "\(diagnosticValue(mailboxFramesDelivered)) / "
                    + "\(diagnosticValue(mailboxFramesCoalesced)) / "
                    + "\(diagnosticValue(mailboxFramesEvicted))"
            )
            SessionDiagnosticsLatencyRow(
                label: "Client frame-event gap p95 / max",
                latency: clientFrameEventGap
            )
            SessionDiagnosticsMetricRow(
                label: "Desktop updates / superseded client frames",
                value: "\(desktopViewUpdates) / \(clientFramesSupersededBeforeDesktopView)"
            )
        }
    }
}

struct SessionDiagnosticsRendererSection: View {
    let metrics: SessionDiagnosticsSwiftSpiceMetrics?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            SessionDiagnosticsSectionHeader(title: "Renderer")
            SessionDiagnosticsMetricRow(
                label: "Observed backing / video policy",
                value: backingAndVideoPolicy
            )
            SessionDiagnosticsMetricRow(
                label: "Readbacks / pool exhausted / GPU errors",
                value: "\(diagnosticValue(metrics?.cpuMaterializations)) / "
                    + "\(diagnosticValue(metrics?.poolExhaustions)) / "
                    + "\(diagnosticValue(metrics?.gpuErrors))"
            )
            SessionDiagnosticsMetricRow(
                label: "Metal presented / superseded / errors",
                value: "\(diagnosticValue(metrics?.metalPresentedFrames)) / "
                    + "\(diagnosticValue(metrics?.metalFramesSupersededBeforeDraw)) / "
                    + "\(diagnosticValue(metrics?.metalPresentationErrors))"
            )
            SessionDiagnosticsMetricRow(
                label: "Drawable misses / command failures",
                value: "\(diagnosticValue(metrics?.metalDrawableMisses)) / "
                    + "\(diagnosticValue(metrics?.metalCommandCreationFailures))"
            )
            if let metrics {
                SessionDiagnosticsLatencyRow(
                    label: "View update → Metal commit p95 / max",
                    latency: metrics.viewUpdateToMetalCommit
                )
                SessionDiagnosticsLatencyRow(
                    label: "Metal commit → completion p95 / max",
                    latency: metrics.metalCommitToCompletion
                )
            }
        }
    }

    private var backingAndVideoPolicy: String {
        guard let metrics, metrics.latest.displayChannelCount > 0 else {
            return "— / MJPEG only"
        }
        return metrics.revisionedBackingEnabled
            ? "Revisioned IOSurface / MJPEG only"
            : "Data / MJPEG only"
    }
}

struct SessionDiagnosticsAdvancedVideoSection: View {
    let metrics: SessionDiagnosticsSwiftSpiceMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            SessionDiagnosticsSectionHeader(title: "Advanced video")
            SessionDiagnosticsMetricRow(
                label: "VT decoded / dropped",
                value: "\(metrics.videoDecodedFrames) / \(metrics.videoDroppedFrames)"
            )
            SessionDiagnosticsMetricRow(
                label: "VT sessions hardware / software",
                value: "\(metrics.videoHardwareSessions) / \(metrics.videoSoftwareSessions)"
            )
            SessionDiagnosticsMetricRow(
                label: "Native / CPU fallback / Metal disabled",
                value: "\(metrics.nativeVideoFrames) / "
                    + "\(metrics.advancedCPUFallbackFrames) / "
                    + "\(metrics.metalGenerationDisableCount)"
            )
        }
    }
}

private struct SessionDiagnosticsSectionHeader: View {
    let title: LocalizedStringResource

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

private func diagnosticValue(_ value: UInt64?) -> String {
    value.map { String($0) } ?? "—"
}

private func diagnosticValue(_ value: Int?) -> String {
    value.map { String($0) } ?? "—"
}

private func diagnosticValue(_ value: UInt32?) -> String {
    value.map(String.init) ?? "—"
}

private func diagnosticValue(_ value: Bool?) -> String {
    value.map { $0 ? "Yes" : "No" } ?? "—"
}

private struct SessionDiagnosticsLatencyRow: View {
    let label: LocalizedStringResource
    let latency: SpiceLatencySummary
    @Environment(\.locale) private var locale

    var body: some View {
        SessionDiagnosticsMetricRow(
            label: label,
            value: latency.sampleCount == 0
                ? "—"
                : "\(formatted(latency.p95Milliseconds)) / "
                    + "\(formatted(latency.maximumMilliseconds)) ms"
        )
    }

    private func formatted(_ milliseconds: Double?) -> String {
        guard let milliseconds else { return "n/a" }
        return milliseconds.formatted(
            .number
                .precision(.fractionLength(1))
                .locale(locale)
        )
    }
}

private struct SessionDiagnosticsMetricRow: View {
    let label: LocalizedStringResource
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value))
    }
}

struct SessionDiagnosticsNotice: View {
    var body: some View {
        Text("VDAgent metrics never contain clipboard text. Agent snapshot counters and fixed failure categories cover the current Agent manager lifetime; UI event counters begin when Diagnostics is enabled. Send completion is local only; Motion ACK is aggregate, not per-event RTT. Display counters rebase at the first best-effort SwiftSpice sample; timing summaries cover the current SwiftSpice session. Sample age shows possible terminal staleness. Channel-state samples include the last observation from retired channels. SwiftSpice coalesces publisher work on a 16 ms interval; receive timing begins only after ChannelConnection returns a complete framed message. Mailbox and Metal counters expose later-stage coalescing and presentation. VideoToolbox counters cover advanced video, not MJPEG. Server-to-framed-receive timing, AsyncStream resume-to-client scheduling, and display-vsync completion remain unmeasured. MainActor is 100 ms timer scheduling delay.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
