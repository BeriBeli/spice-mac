// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import SpiceController

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
