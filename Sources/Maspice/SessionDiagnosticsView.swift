// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import SpiceController
import SwiftSpice
import SwiftUI

struct SessionDiagnosticsView: View {
    let snapshot: SpiceClientDiagnosticsSnapshot
    let onCopy: () -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            diagnosticsContent
            ScrollView {
                diagnosticsContent
            }
            .scrollIndicators(.visible)
        }
        .padding(10)
        .frame(
            minWidth: 310,
            idealWidth: 340,
            maxWidth: 380,
            maxHeight: 400,
            alignment: .topLeading
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .padding(12)
    }

    private var diagnosticsContent: some View {
        let swiftSpiceMetrics = snapshot.swiftSpiceDiagnostics.map(
            SessionDiagnosticsSwiftSpiceMetrics.init
        )

        return VStack(alignment: .leading, spacing: 8) {
            SessionDiagnosticsHeader(isCollecting: snapshot.isEnabled)
            Divider()
            SessionDiagnosticsInputSection(
                pendingCount: "\(snapshot.pendingInputCount)",
                maximumPendingCount: "\(snapshot.maximumPendingInputCount)",
                queueWait: snapshot.inputQueueWait,
                sendDuration: snapshot.inputSendDuration,
                submitted: "\(snapshot.inputSubmitted)",
                sent: "\(snapshot.inputSent)",
                coalesced: "\(snapshot.inputCoalesced)",
                motionSent: "\(snapshot.motionSent)",
                motionAcknowledgements: "\(snapshot.mouseMotionAcknowledgements)",
                sendFailures: "\(snapshot.sendFailures)"
            )
            Divider()
            SessionDiagnosticsAgentSection(metrics: snapshot.agent)
            Divider()
            SessionDiagnosticsDisplaySection(
                publisherSubmissions: swiftSpiceMetrics?.publisherSubmissions,
                publisherEmittedFrames: swiftSpiceMetrics?.publisherEmittedFrames,
                publisherStaleSnapshots: swiftSpiceMetrics?.publisherStaleSnapshots,
                publisherPendingEvictions: swiftSpiceMetrics?.publisherPendingEvictions,
                publisherPendingSurfaces: swiftSpiceMetrics?.publisherPendingSurfaces,
                publisherFramedReceiveBatchStartGap:
                    swiftSpiceMetrics?.publisherFramedReceiveBatchStartGap,
                publisherMessageReceiveToSurfaceReady:
                    swiftSpiceMetrics?.publisherMessageReceiveToSurfaceReady,
                publisherSurfaceReadyToSubmit:
                    swiftSpiceMetrics?.publisherSurfaceReadyToSubmit,
                mailboxFramesSent: swiftSpiceMetrics?.mailboxFramesSent,
                mailboxFramesDelivered: swiftSpiceMetrics?.mailboxFramesDelivered,
                mailboxFramesCoalesced: swiftSpiceMetrics?.mailboxFramesCoalesced,
                mailboxFramesEvicted: swiftSpiceMetrics?.mailboxFramesEvicted,
                clientFrameEvents: "\(snapshot.clientFrameEvents)",
                clientFrameEventGap: snapshot.clientFrameEventGap,
                desktopViewUpdates: "\(snapshot.desktopViewUpdates)",
                clientFramesSupersededBeforeDesktopView:
                    "\(snapshot.clientFramesSupersededBeforeDesktopView)"
            )
            Divider()
            SessionDiagnosticsRendererSection(metrics: swiftSpiceMetrics)
            if let swiftSpiceMetrics, swiftSpiceMetrics.hasAdvancedVideoActivity {
                Divider()
                SessionDiagnosticsAdvancedVideoSection(metrics: swiftSpiceMetrics)
            }
            Divider()
            SessionDiagnosticsNotice()
            Button(action: onCopy) {
                Label("Copy Summary", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint("Copies only aggregate session counters and latency values.")
        }
    }
}

@MainActor
enum SessionDiagnosticsClipboard {
    static func copy(_ summary: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(summary, forType: .string)
    }
}

extension SpiceClientDiagnosticsSnapshot {
    /// A deliberately metadata-free summary containing only aggregate
    /// counters, gauges, and latency summaries from this session snapshot.
    var diagnosticsSummary: String {
        var lines = [
            "Maspice session diagnostics",
            "enabled=\(isEnabled)",
            "scope=best_effort_aggregate_in_memory",
            "display_epoch=first_swiftspice_sample",
            "display_timing_epoch=current_swiftspice_session",
            "input_send_scope=local_completion_not_rtt",
            "motion_ack_scope=aggregate_not_per_event_rtt",
            "publisher_emit_scope=through_session_mailbox_send_not_client_consumption",
            "display_receive_scope=channel_connection_framed_message_completion",
            "display_decode_scope=receive_completion_through_surface_apply_before_ack",
            "publisher_submit_scope=display_actor_to_publisher_actor_entry",
            "video_scope=advanced_h264_h265_not_mjpeg",
            "channel_state_scope=active_plus_retired_last_observation",
            "agent_scope=state_and_content_free_event_counts",
            "agent_snapshot_counter_epoch=current_agent_manager_lifetime",
            "agent_event_counter_epoch=diagnostics_enable",
            "unmeasured=server_to_framed_receive_async_stream_resume_to_client_and_display_vsync_timing",
            "input_submitted=\(inputSubmitted)",
            "input_sent=\(inputSent)",
            "input_coalesced=\(inputCoalesced)",
            "motion_submitted=\(motionSubmitted)",
            "motion_sent=\(motionSent)",
            "motion_acknowledgements=\(mouseMotionAcknowledgements)",
            "input_queue_current=\(pendingInputCount)",
            "input_queue_maximum=\(maximumPendingInputCount)",
            Self.latencySummary(name: "input_queue_wait", value: inputQueueWait),
            Self.latencySummary(name: "input_send", value: inputSendDuration),
            "client_frame_events=\(clientFrameEvents)",
            Self.latencySummary(
                name: "client_frame_event_gap",
                value: clientFrameEventGap
            ),
            Self.latencySummary(
                name: "main_actor_scheduling_delay",
                value: mainActorSchedulingDelay
            ),
            "desktop_view_updates=\(desktopViewUpdates)",
            "client_frames_superseded_before_desktop_view=\(clientFramesSupersededBeforeDesktopView)",
            Self.latencySummary(
                name: "client_to_desktop_view_update",
                value: clientToDesktopViewUpdate
            ),
            "send_failures=\(sendFailures)",
            "agent_support_observed=\(agent.supportObserved)",
            "agent_connected=\(agent.agentConnected)",
            "agent_capability_announcement_received=\(agent.capabilityAnnouncementReceived)",
            "agent_monitor_configuration_supported=\(agent.monitorConfigurationSupported)",
            "agent_clipboard_state=\(agent.clipboardState.rawValue)",
            "agent_connect_transitions=\(agent.agentConnectTransitions)",
            "agent_disconnect_transitions=\(agent.agentDisconnectTransitions)",
            "agent_manager_start_failures=\(agent.agentManagerStartFailures)",
            "agent_capability_announcements_attempted=\(agent.capabilityAnnouncementsAttempted)",
            "agent_capability_announcements_sent=\(agent.capabilityAnnouncementsSent)",
            "agent_capability_announcement_failures=\(agent.capabilityAnnouncementFailures)",
            "agent_inbound_messages=\(agent.inboundMessages)",
            "agent_inbound_current_protocol_messages=\(agent.inboundCurrentProtocolMessages)",
            "agent_inbound_unexpected_protocol_messages=\(agent.inboundUnexpectedProtocolMessages)",
            "agent_inbound_capability_announcements=\(agent.inboundCapabilityAnnouncements)",
            "agent_inbound_clipboard_messages=\(agent.inboundClipboardMessages)",
            "agent_inbound_clipboard_data_messages=\(agent.inboundClipboardDataMessages)",
            "agent_inbound_clipboard_grab_messages=\(agent.inboundClipboardGrabMessages)",
            "agent_inbound_clipboard_request_messages=\(agent.inboundClipboardRequestMessages)",
            "agent_inbound_clipboard_release_messages=\(agent.inboundClipboardReleaseMessages)",
            "agent_inbound_monitor_replies=\(agent.inboundMonitorReplies)",
            "agent_inbound_file_transfer_messages=\(agent.inboundFileTransferMessages)",
            "agent_inbound_other_messages=\(agent.inboundOtherMessages)",
            "agent_inbound_decode_failures=\(agent.inboundDecodeFailures)",
            "agent_peer_legacy_clipboard_capability=\(Self.optionalBool(agent.peerLegacyClipboardCapability))",
            "agent_peer_clipboard_by_demand_capability=\(Self.optionalBool(agent.peerClipboardByDemandCapability))",
            "agent_manager_clipboard_failures=\(agent.managerClipboardFailures)",
            "agent_last_manager_clipboard_failure_category=\(agent.lastManagerClipboardFailureCategory?.rawValue ?? "n/a")",
            "agent_last_inbound_protocol_id=\(Self.optionalUInt32(agent.lastInboundProtocolID))",
            "agent_last_inbound_message_type=\(Self.optionalUInt32(agent.lastInboundMessageType))",
            "agent_clipboard_ready_events=\(agent.clipboardReadyEvents)",
            "agent_clipboard_unavailable_events=\(agent.clipboardUnavailableEvents)",
            "agent_clipboard_local_text_offer_events=\(agent.clipboardLocalTextOfferEvents)",
            "agent_clipboard_guest_text_events=\(agent.clipboardGuestTextEvents)",
            "agent_clipboard_oversized_local_text_events=\(agent.clipboardOversizedLocalTextEvents)",
            "agent_clipboard_failures=\(agent.clipboardFailures)",
            "agent_monitor_configuration_requests=\(agent.monitorConfigurationRequests)",
            "agent_monitor_configuration_blocked=\(agent.monitorConfigurationBlocked)",
            "agent_monitor_configuration_queued=\(agent.monitorConfigurationQueued)",
            "agent_monitor_configuration_sent=\(agent.monitorConfigurationSent)",
            "agent_monitor_configuration_acknowledged=\(agent.monitorConfigurationAcknowledged)",
            "agent_monitor_configuration_rejected=\(agent.monitorConfigurationRejected)",
            "agent_monitor_configuration_unsupported=\(agent.monitorConfigurationUnsupported)",
            "agent_monitor_configuration_failures=\(agent.monitorConfigurationFailures)",
            "agent_monitor_configuration_protocol_failures=\(agent.monitorConfigurationProtocolFailures)",
        ]

        if let swiftSpiceDiagnostics {
            lines.append(contentsOf:
                SessionDiagnosticsSwiftSpiceMetrics(swiftSpiceDiagnostics).summaryLines
            )
        }

        return lines.joined(separator: "\n")
    }

    private static func latencySummary(
        name: String,
        value: SpiceLatencySummary
    ) -> String {
        [
            "\(name)_samples=\(value.sampleCount)",
            "\(name)_p95_ms=\(stableMilliseconds(value.p95Milliseconds))",
            "\(name)_max_ms=\(stableMilliseconds(value.maximumMilliseconds))",
        ].joined(separator: "\n")
    }

    private static func stableMilliseconds(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func optionalUInt32(_ value: UInt32?) -> String {
        value.map(String.init) ?? "n/a"
    }

    private static func optionalBool(_ value: Bool?) -> String {
        value.map(String.init) ?? "n/a"
    }
}

private struct SessionDiagnosticsSwiftSpiceMetrics {
    let baseline: SpiceSessionDiagnostics
    let latest: SpiceSessionDiagnostics
    let latestSampleAgeMilliseconds: Double

    init(_ diagnostics: SpiceClientSwiftSpiceDiagnostics) {
        baseline = diagnostics.baseline
        latest = diagnostics.latest
        latestSampleAgeMilliseconds = diagnostics.latestSampleAgeMilliseconds
    }

    var publisherSubmissions: UInt64 {
        counterDelta(latest.publisherSubmissions, from: baseline.publisherSubmissions)
    }

    var publisherSnapshotAttempts: UInt64 {
        counterDelta(
            latest.publisherSnapshotAttempts,
            from: baseline.publisherSnapshotAttempts
        )
    }

    var publisherEmittedFrames: UInt64 {
        counterDelta(latest.publisherEmittedFrames, from: baseline.publisherEmittedFrames)
    }

    var publisherStaleSnapshots: UInt64 {
        counterDelta(latest.publisherStaleSnapshots, from: baseline.publisherStaleSnapshots)
    }

    var publisherPendingEvictions: UInt64 {
        counterDelta(
            latest.publisherPendingEvictions,
            from: baseline.publisherPendingEvictions
        )
    }

    var publisherPendingSurfaces: Int { latest.publisherPendingSurfaces }
    var publisherFlushes: UInt64 {
        counterDelta(latest.publisherFlushes, from: baseline.publisherFlushes)
    }
    var publisherFlushesWithoutEmission: UInt64 {
        counterDelta(
            latest.publisherFlushesWithoutEmission,
            from: baseline.publisherFlushesWithoutEmission
        )
    }
    var mailboxFramesSent: UInt64 {
        counterDelta(latest.mailboxFramesSent, from: baseline.mailboxFramesSent)
    }
    var mailboxFramesDelivered: UInt64 {
        counterDelta(latest.mailboxFramesDelivered, from: baseline.mailboxFramesDelivered)
    }
    var mailboxFramesCoalesced: UInt64 {
        counterDelta(latest.mailboxFramesCoalesced, from: baseline.mailboxFramesCoalesced)
    }
    var mailboxFramesEvicted: UInt64 {
        counterDelta(latest.mailboxFramesEvicted, from: baseline.mailboxFramesEvicted)
    }
    var publisherBatchStartGap: SpiceLatencySummary {
        Self.clientSummary(latest.publisherBatchStartGap)
    }
    var publisherFramedReceiveBatchStartGap: SpiceLatencySummary {
        Self.clientSummary(latest.publisherFramedReceiveBatchStartGap)
    }
    var publisherMessageReceiveToSurfaceReady: SpiceLatencySummary {
        Self.clientSummary(latest.publisherMessageReceiveToSurfaceReady)
    }
    var publisherSurfaceReadyToSubmit: SpiceLatencySummary {
        Self.clientSummary(latest.publisherSurfaceReadyToSubmit)
    }
    var publisherFlushStartGap: SpiceLatencySummary {
        Self.clientSummary(latest.publisherFlushStartGap)
    }
    var publisherFlushSchedulingDelay: SpiceLatencySummary {
        Self.clientSummary(latest.publisherFlushSchedulingDelay)
    }
    var publisherSnapshotDuration: SpiceLatencySummary {
        Self.clientSummary(latest.publisherSnapshotDuration)
    }
    var publisherEmitDuration: SpiceLatencySummary {
        Self.clientSummary(latest.publisherEmitDuration)
    }
    var mailboxFrameQueueDelay: SpiceLatencySummary {
        Self.clientSummary(latest.mailboxFrameQueueDelay)
    }
    var revisionedBackingEnabled: Bool { latest.revisionedBackingEnabled }

    var cpuMaterializations: UInt64 {
        counterDelta(latest.cpuMaterializations, from: baseline.cpuMaterializations)
    }

    var cpuMaterializationBytes: UInt64 {
        counterDelta(
            latest.cpuMaterializationBytes,
            from: baseline.cpuMaterializationBytes
        )
    }

    var poolExhaustions: UInt64 {
        counterDelta(latest.poolExhaustions, from: baseline.poolExhaustions)
    }

    var gpuErrors: UInt64 {
        counterDelta(latest.gpuErrors, from: baseline.gpuErrors)
    }

    var metalPresentedFrames: UInt64 {
        counterDelta(latest.metalPresentedFrames, from: baseline.metalPresentedFrames)
    }
    var metalPresentationErrors: UInt64 {
        counterDelta(latest.metalPresentationErrors, from: baseline.metalPresentationErrors)
    }
    var metalFramesSupersededBeforeDraw: UInt64 {
        counterDelta(
            latest.metalFramesSupersededBeforeDraw,
            from: baseline.metalFramesSupersededBeforeDraw
        )
    }
    var metalDrawableMisses: UInt64 {
        counterDelta(latest.metalDrawableMisses, from: baseline.metalDrawableMisses)
    }
    var metalCommandCreationFailures: UInt64 {
        counterDelta(
            latest.metalCommandCreationFailures,
            from: baseline.metalCommandCreationFailures
        )
    }
    var viewUpdateToMetalCommit: SpiceLatencySummary {
        Self.clientSummary(latest.viewUpdateToMetalCommit)
    }
    var metalCommitToCompletion: SpiceLatencySummary {
        Self.clientSummary(latest.metalCommitToCompletion)
    }

    var nativeVideoFrames: UInt64 {
        counterDelta(latest.nativeVideoFrames, from: baseline.nativeVideoFrames)
    }

    var nativeVideoFallbacks: UInt64 {
        counterDelta(latest.nativeVideoFallbacks, from: baseline.nativeVideoFallbacks)
    }

    var videoDecoderSessionCreations: UInt64 {
        counterDelta(
            latest.videoDecoderSessionCreations,
            from: baseline.videoDecoderSessionCreations
        )
    }

    var videoHardwareSessions: UInt64 {
        counterDelta(latest.videoHardwareSessions, from: baseline.videoHardwareSessions)
    }

    var videoSoftwareSessions: UInt64 {
        counterDelta(latest.videoSoftwareSessions, from: baseline.videoSoftwareSessions)
    }

    var videoHardwareQueryFailures: UInt64 {
        counterDelta(
            latest.videoHardwareQueryFailures,
            from: baseline.videoHardwareQueryFailures
        )
    }

    var videoDecodedFrames: UInt64 {
        counterDelta(latest.videoDecodedFrames, from: baseline.videoDecodedFrames)
    }

    var videoDroppedFrames: UInt64 {
        counterDelta(latest.videoDroppedFrames, from: baseline.videoDroppedFrames)
    }

    var videoCPUMaterializations: UInt64 {
        counterDelta(
            latest.videoCPUMaterializations,
            from: baseline.videoCPUMaterializations
        )
    }

    var advancedCPUFallbackFrames: UInt64 {
        counterDelta(
            latest.advancedCPUFallbackFrames,
            from: baseline.advancedCPUFallbackFrames
        )
    }

    var metalGenerationDisableCount: UInt64 {
        counterDelta(
            latest.metalGenerationDisableCount,
            from: baseline.metalGenerationDisableCount
        )
    }

    var hasAdvancedVideoActivity: Bool {
        nativeVideoFrames != 0
            || nativeVideoFallbacks != 0
            || videoDecoderSessionCreations != 0
            || videoHardwareSessions != 0
            || videoSoftwareSessions != 0
            || videoHardwareQueryFailures != 0
            || videoDecodedFrames != 0
            || videoDroppedFrames != 0
            || videoCPUMaterializations != 0
            || advancedCPUFallbackFrames != 0
            || metalGenerationDisableCount != 0
    }

    var summaryLines: [String] {
        var lines = [
            "swiftspice_display_channel_instances=\(latest.displayChannelCount)",
            "swiftspice_latest_sample_age_ms=\(stableSampleAgeMilliseconds)",
            "swiftspice_publisher_submissions_delta=\(publisherSubmissions)",
            "swiftspice_publisher_snapshot_attempts_delta=\(publisherSnapshotAttempts)",
            "swiftspice_publisher_emitted_frames_delta=\(publisherEmittedFrames)",
            "swiftspice_publisher_stale_snapshots_delta=\(publisherStaleSnapshots)",
            "swiftspice_publisher_pending_evictions_delta=\(publisherPendingEvictions)",
            "swiftspice_publisher_pending_surfaces_sample=\(publisherPendingSurfaces)",
            "swiftspice_publisher_flushes_delta=\(publisherFlushes)",
            "swiftspice_publisher_flushes_without_emission_delta=\(publisherFlushesWithoutEmission)",
            latencySummary(name: "swiftspice_publisher_batch_start_gap", value: publisherBatchStartGap),
            latencySummary(name: "swiftspice_framed_receive_batch_start_gap", value: publisherFramedReceiveBatchStartGap),
            latencySummary(name: "swiftspice_message_receive_to_surface_ready", value: publisherMessageReceiveToSurfaceReady),
            latencySummary(name: "swiftspice_surface_ready_to_publisher_submit", value: publisherSurfaceReadyToSubmit),
            latencySummary(name: "swiftspice_publisher_flush_start_gap", value: publisherFlushStartGap),
            latencySummary(name: "swiftspice_publisher_flush_scheduling_delay", value: publisherFlushSchedulingDelay),
            latencySummary(name: "swiftspice_publisher_snapshot_duration", value: publisherSnapshotDuration),
            latencySummary(name: "swiftspice_publisher_emit_duration", value: publisherEmitDuration),
            "swiftspice_mailbox_frames_sent_delta=\(mailboxFramesSent)",
            "swiftspice_mailbox_frames_delivered_delta=\(mailboxFramesDelivered)",
            "swiftspice_mailbox_frames_coalesced_delta=\(mailboxFramesCoalesced)",
            "swiftspice_mailbox_frames_evicted_delta=\(mailboxFramesEvicted)",
            latencySummary(name: "swiftspice_mailbox_frame_queue_delay", value: mailboxFrameQueueDelay),
            "swiftspice_revisioned_backing_observed=\(revisionedBackingEnabled)",
            "swiftspice_cpu_materializations_delta=\(cpuMaterializations)",
            "swiftspice_cpu_materialization_bytes_delta=\(cpuMaterializationBytes)",
            "swiftspice_pool_exhaustions_delta=\(poolExhaustions)",
            "swiftspice_in_flight_leases_observed_max=\(latest.inFlightLeases)",
            "swiftspice_gpu_errors_delta=\(gpuErrors)",
            "swiftspice_metal_presented_frames_delta=\(metalPresentedFrames)",
            "swiftspice_metal_presentation_errors_delta=\(metalPresentationErrors)",
            "swiftspice_metal_frames_superseded_before_draw_delta=\(metalFramesSupersededBeforeDraw)",
            "swiftspice_metal_drawable_misses_delta=\(metalDrawableMisses)",
            "swiftspice_metal_command_creation_failures_delta=\(metalCommandCreationFailures)",
            latencySummary(name: "swiftspice_view_update_to_metal_commit", value: viewUpdateToMetalCommit),
            latencySummary(name: "swiftspice_metal_commit_to_completion", value: metalCommitToCompletion),
            "swiftspice_surface_allocated_bytes_gauge=\(latest.surfaceAllocatedBytes)",
            "swiftspice_surface_budget_bytes_limit=\(latest.maximumSurfaceBytes)",
        ]

        if hasAdvancedVideoActivity {
            lines.append(contentsOf: [
                "swiftspice_native_video_frames_delta=\(nativeVideoFrames)",
                "swiftspice_native_video_fallbacks_delta=\(nativeVideoFallbacks)",
                "swiftspice_vt_session_creations_delta=\(videoDecoderSessionCreations)",
                "swiftspice_vt_hardware_sessions_delta=\(videoHardwareSessions)",
                "swiftspice_vt_software_sessions_delta=\(videoSoftwareSessions)",
                "swiftspice_vt_hardware_query_failures_delta=\(videoHardwareQueryFailures)",
                "swiftspice_vt_decoded_frames_delta=\(videoDecodedFrames)",
                "swiftspice_vt_dropped_frames_delta=\(videoDroppedFrames)",
                "swiftspice_vt_cpu_materializations_delta=\(videoCPUMaterializations)",
                "swiftspice_advanced_cpu_fallback_frames_delta=\(advancedCPUFallbackFrames)",
                "swiftspice_metal_generation_disable_count_delta=\(metalGenerationDisableCount)",
            ])
        }

        return lines
    }

    private var stableSampleAgeMilliseconds: String {
        String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            latestSampleAgeMilliseconds
        )
    }

    private static func clientSummary(_ value: SpiceTimingSummary) -> SpiceLatencySummary {
        return SpiceLatencySummary(
            sampleCount: value.sampleCount,
            p95Milliseconds: value.p95Milliseconds,
            maximumMilliseconds: value.maximumMilliseconds
        )
    }

    private func latencySummary(name: String, value: SpiceLatencySummary) -> String {
        [
            "\(name)_samples=\(value.sampleCount)",
            "\(name)_p95_ms=\(stableMilliseconds(value.p95Milliseconds))",
            "\(name)_max_ms=\(stableMilliseconds(value.maximumMilliseconds))",
        ].joined(separator: "\n")
    }

    private func stableMilliseconds(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

private func counterDelta(_ current: UInt64, from baseline: UInt64) -> UInt64 {
    current >= baseline ? current - baseline : current
}

private struct SessionDiagnosticsHeader: View {
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

private struct SessionDiagnosticsInputSection: View {
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

private struct SessionDiagnosticsAgentSection: View {
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

private struct SessionDiagnosticsDisplaySection: View {
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

private struct SessionDiagnosticsRendererSection: View {
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

private struct SessionDiagnosticsAdvancedVideoSection: View {
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

private struct SessionDiagnosticsNotice: View {
    var body: some View {
        Text("VDAgent metrics never contain clipboard text. Agent snapshot counters and fixed failure categories cover the current Agent manager lifetime; UI event counters begin when Diagnostics is enabled. Send completion is local only; Motion ACK is aggregate, not per-event RTT. Display counters rebase at the first best-effort SwiftSpice sample; timing summaries cover the current SwiftSpice session. Sample age shows possible terminal staleness. Channel-state samples include the last observation from retired channels. SwiftSpice coalesces publisher work on a 16 ms interval; receive timing begins only after ChannelConnection returns a complete framed message. Mailbox and Metal counters expose later-stage coalescing and presentation. VideoToolbox counters cover advanced video, not MJPEG. Server-to-framed-receive timing, AsyncStream resume-to-client scheduling, and display-vsync completion remain unmeasured. MainActor is 100 ms timer scheduling delay.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
