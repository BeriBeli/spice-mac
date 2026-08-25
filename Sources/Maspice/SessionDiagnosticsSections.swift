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
    let metrics: SessionDiagnosticsSwiftSpiceMetrics?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            SessionDiagnosticsSectionHeader(title: "Display pipeline")
            SessionDiagnosticsMetricRow(
                label: "Mutation submit / snapshot / emit",
                value: "\(diagnosticValue(metrics?.publisherSubmissions)) / "
                    + "\(diagnosticValue(metrics?.publisherSnapshotAttempts)) / "
                    + "\(diagnosticValue(metrics?.publisherEmittedFrames))"
            )
            SessionDiagnosticsMetricRow(
                label: "Demand suppressed / pending / prepared coalesces",
                value: "\(diagnosticValue(metrics?.publisherDemandSuppressedSubmissions)) / "
                    + "\(diagnosticValue(metrics?.publisherPendingRevisionCoalesces)) / "
                    + "\(diagnosticValue(metrics?.publisherPreparedFrameCoalesces))"
            )
            SessionDiagnosticsMetricRow(
                label: "Pending / demanded / prepared surfaces",
                value: "\(diagnosticValue(metrics?.publisherPendingSurfaces)) / "
                    + "\(diagnosticValue(metrics?.publisherDemandedSurfaces)) / "
                    + "\(diagnosticValue(metrics?.publisherPreparedFrames))"
            )
            SessionDiagnosticsMetricRow(
                label: "Desktop delivered / stream coalesced / handler",
                value: "\(diagnosticValue(metrics?.desktopDeliveredSnapshots)) / "
                    + "\(diagnosticValue(metrics?.desktopStreamCoalesces)) / "
                    + "\(diagnosticValue(metrics?.desktopHandlerDeliveries))"
            )
            SessionDiagnosticsMetricRow(
                label: "Desktop subscriptions / visible",
                value: "\(diagnosticValue(metrics?.desktopSubscriptions)) / "
                    + "\(diagnosticValue(metrics?.desktopVisibleSubscriptions))"
            )
            if let metrics {
                SessionDiagnosticsLatencyRow(
                    label: "Framed-receive batch gap p95 / max",
                    latency: metrics.publisherFramedReceiveBatchStartGap
                )
                SessionDiagnosticsLatencyRow(
                    label: "Receive → surface ready p95 / max",
                    latency: metrics.publisherMessageReceiveToSurfaceReady
                )
                SessionDiagnosticsLatencyRow(
                    label: "Surface ready → publisher p95 / max",
                    latency: metrics.publisherSurfaceReadyToSubmit
                )
                SessionDiagnosticsLatencyRow(
                    label: "Snapshot preparation p95 / max",
                    latency: metrics.publisherSnapshotDuration
                )
            }
        }
    }
}

struct SessionDiagnosticsRendererSection: View {
    let metrics: SessionDiagnosticsSwiftSpiceMetrics?
    let codecFallbackReconnects: UInt64

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
                label: "Direct IOSurface write bytes",
                value: diagnosticValue(metrics?.directIOSurfaceWriteBytes)
            )
            SessionDiagnosticsMetricRow(
                label: "Metal presented / committed / superseded",
                value: "\(diagnosticValue(metrics?.metalPresentedFrames)) / "
                    + "\(diagnosticValue(metrics?.metalCommandBuffersCommitted)) / "
                    + "\(diagnosticValue(metrics?.metalFramesSupersededBeforeDraw))"
            )
            SessionDiagnosticsMetricRow(
                label: "Drawable miss / GPU busy / presentation error",
                value: "\(diagnosticValue(metrics?.metalDrawableMisses)) / "
                    + "\(diagnosticValue(metrics?.metalGPUBusySkips)) / "
                    + "\(diagnosticValue(metrics?.metalPresentationErrors))"
            )
            SessionDiagnosticsMetricRow(
                label: "Texture cache hit / miss / eviction",
                value: "\(diagnosticValue(metrics?.metalTextureCacheHits)) / "
                    + "\(diagnosticValue(metrics?.metalTextureCacheMisses)) / "
                    + "\(diagnosticValue(metrics?.metalTextureCacheEvictions))"
            )
            SessionDiagnosticsMetricRow(
                label: "Display-link wake / tick / idle pause",
                value: "\(diagnosticValue(metrics?.desktopDisplayLinkWakeups)) / "
                    + "\(diagnosticValue(metrics?.desktopDisplayLinkTicks)) / "
                    + "\(diagnosticValue(metrics?.desktopDisplayLinkIdlePauses))"
            )
            SessionDiagnosticsMetricRow(
                label: "Immediate desktop selections",
                value: diagnosticValue(metrics?.desktopImmediateSelections)
            )
            SessionDiagnosticsMetricRow(
                label: "CPU presentation fallback / command failure",
                value: "\(diagnosticValue(metrics?.cpuFallbackFrames)) / "
                    + "\(diagnosticValue(metrics?.metalCommandCreationFailures))"
            )
            SessionDiagnosticsMetricRow(
                label: "Codec fallback reconnects",
                value: "\(codecFallbackReconnects)"
            )
            if let metrics {
                SessionDiagnosticsLatencyRow(
                    label: "Desktop ready → revision selection p95 / max",
                    latency: metrics.desktopReadyToRevisionSelection
                )
                SessionDiagnosticsLatencyRow(
                    label: "Revision selection → Metal commit p95 / max",
                    latency: metrics.revisionSelectionToMetalCommit
                )
                SessionDiagnosticsLatencyRow(
                    label: "Metal commit → completion p95 / max",
                    latency: metrics.metalCommitToCompletion
                )
                SessionDiagnosticsLatencyRow(
                    label: "Revision request → presented p95 / max",
                    latency: metrics.metalRequestToPresented
                )
            }
        }
    }

    private var backingAndVideoPolicy: String {
        guard let metrics, metrics.latest.displayChannelCount > 0 else {
            return "— / H.264 + MJPEG fallback"
        }
        return metrics.revisionedBackingEnabled
            ? "Revisioned IOSurface / H.264 + MJPEG fallback"
            : "Data / H.264 + MJPEG fallback"
    }
}

struct SessionDiagnosticsVideoCodecSection: View {
    let metrics: SessionDiagnosticsSwiftSpiceMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            SessionDiagnosticsSectionHeader(title: "Video codecs")
            SessionDiagnosticsMetricRow(
                label: "VT decoded / dropped",
                value: "\(metrics.videoDecodedFrames) / \(metrics.videoDroppedFrames)"
            )
            SessionDiagnosticsMetricRow(
                label: "VT sessions hardware / software",
                value: "\(metrics.videoHardwareSessions) / \(metrics.videoSoftwareSessions)"
            )
            SessionDiagnosticsMetricRow(
                label: "Advanced video Metal-presented",
                value: "\(metrics.advancedVideoPresentedFrames)"
            )
            SessionDiagnosticsMetricRow(
                label: "Native / CPU fallback / Metal disabled",
                value: "\(metrics.nativeVideoFrames) / "
                    + "\(metrics.advancedCPUFallbackFrames) / "
                    + "\(metrics.metalGenerationDisableCount)"
            )
            SessionDiagnosticsMetricRow(
                label: "MJPEG decoded / IOSurface / Data fallback",
                value: "\(metrics.mjpegDecodedFrames) / "
                    + "\(metrics.mjpegIOSurfaceFrames) / "
                    + "\(metrics.mjpegDataFallbacks)"
            )
            SessionDiagnosticsMetricRow(
                label: "MJPEG handles / IOSurface allocations / peak decode",
                value: "\(metrics.mjpegDecoderHandleCreations) / "
                    + "\(metrics.mjpegIOSurfaceAllocations) / "
                    + "\(metrics.mjpegPeakConcurrentDecodes)"
            )
            SessionDiagnosticsMetricRow(
                label: "MJPEG superseded before decode",
                value: "\(metrics.mjpegFramesSupersededBeforeDecode)"
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
        Text("VDAgent metrics never contain clipboard text. Agent snapshot counters and fixed failure categories cover the current Agent manager lifetime; UI event counters begin when Diagnostics is enabled. Send completion is local only; Motion ACK is aggregate, not per-event RTT. Display counters rebase at the first best-effort SwiftSpice sample; timing summaries cover the current SwiftSpice session. Sample age shows possible terminal staleness. Channel-state samples include the last observation from retired channels. SwiftSpice coalesces desktop revisions on display demand and suppresses snapshots while hidden; frame and cursor traffic bypass SwiftUI Observation. Receive timing begins only after ChannelConnection returns a complete framed message. Source, display-link, Metal, VideoToolbox, and MJPEG counters expose coalescing, GPU back-pressure, buffer reuse, and actual presentation. Server-to-framed-receive timing remains unmeasured. MainActor is 100 ms timer scheduling delay.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
