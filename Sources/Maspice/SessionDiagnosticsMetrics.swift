// SPDX-License-Identifier: MIT
import Foundation
import SpiceController
import SwiftSpice

struct SessionDiagnosticsSwiftSpiceMetrics {
    let baseline: SpiceSessionDiagnostics
    let latest: SpiceSessionDiagnostics
    let latestSampleAgeMilliseconds: Double

    init(_ diagnostics: SpiceClientSwiftSpiceDiagnostics) {
        baseline = diagnostics.baseline
        latest = diagnostics.latest
        latestSampleAgeMilliseconds = diagnostics.latestSampleAgeMilliseconds
    }

    var publisherSubmissions: UInt64 { delta(\.publisherSubmissions) }
    var publisherSnapshotAttempts: UInt64 { delta(\.publisherSnapshotAttempts) }
    var publisherEmittedFrames: UInt64 { delta(\.publisherEmittedFrames) }
    var publisherEmittedIOSurfaceFrames: UInt64 { delta(\.publisherEmittedIOSurfaceFrames) }
    var publisherEmittedCPUOnlyFrames: UInt64 { delta(\.publisherEmittedCPUOnlyFrames) }
    var publisherStaleSnapshots: UInt64 { delta(\.publisherStaleSnapshots) }
    var publisherPendingEvictions: UInt64 { delta(\.publisherPendingEvictions) }
    var publisherDemandSuppressedSubmissions: UInt64 {
        delta(\.publisherDemandSuppressedSubmissions)
    }
    var publisherPendingRevisionCoalesces: UInt64 {
        delta(\.publisherPendingRevisionCoalesces)
    }
    var publisherPreparedFrameCoalesces: UInt64 {
        delta(\.publisherPreparedFrameCoalesces)
    }
    var publisherPendingSurfaces: Int { latest.publisherPendingSurfaces }
    var publisherDemandedSurfaces: Int { latest.publisherDemandedSurfaces }
    var publisherPreparedFrames: Int { latest.publisherPreparedFrames }

    var desktopDeliveredSnapshots: UInt64 { delta(\.desktopDeliveredSnapshots) }
    var desktopStreamCoalesces: UInt64 { delta(\.desktopStreamCoalesces) }
    var desktopHandlerDeliveries: UInt64 { delta(\.desktopHandlerDeliveries) }
    var desktopSubscriptions: Int { latest.desktopSubscriptions }
    var desktopVisibleSubscriptions: Int { latest.desktopVisibleSubscriptions }

    var publisherFramedReceiveBatchStartGap: SpiceLatencySummary {
        Self.clientSummary(latest.publisherFramedReceiveBatchStartGap)
    }
    var publisherMessageReceiveToSurfaceReady: SpiceLatencySummary {
        Self.clientSummary(latest.publisherMessageReceiveToSurfaceReady)
    }
    var publisherSurfaceReadyToSubmit: SpiceLatencySummary {
        Self.clientSummary(latest.publisherSurfaceReadyToSubmit)
    }
    var publisherSnapshotDuration: SpiceLatencySummary {
        Self.clientSummary(latest.publisherSnapshotDuration)
    }

    var revisionedBackingEnabled: Bool { latest.revisionedBackingEnabled }
    var cpuMaterializations: UInt64 { delta(\.cpuMaterializations) }
    var cpuMaterializationBytes: UInt64 { delta(\.cpuMaterializationBytes) }
    var poolExhaustions: UInt64 { delta(\.poolExhaustions) }
    var gpuErrors: UInt64 { delta(\.gpuErrors) }

    var metalPresentedFrames: UInt64 { delta(\.metalPresentedFrames) }
    var advancedVideoPresentedFrames: UInt64 { delta(\.advancedVideoPresentedFrames) }
    var metalPresentationErrors: UInt64 { delta(\.metalPresentationErrors) }
    var metalFramesSupersededBeforeDraw: UInt64 { delta(\.metalFramesSupersededBeforeDraw) }
    var metalDrawableMisses: UInt64 { delta(\.metalDrawableMisses) }
    var metalCommandCreationFailures: UInt64 { delta(\.metalCommandCreationFailures) }
    var metalCommandBuffersCommitted: UInt64 { delta(\.metalCommandBuffersCommitted) }
    var metalTextureCacheHits: UInt64 { delta(\.metalTextureCacheHits) }
    var metalTextureCacheMisses: UInt64 { delta(\.metalTextureCacheMisses) }
    var metalTextureCacheEvictions: UInt64 { delta(\.metalTextureCacheEvictions) }
    var metalGPUBusySkips: UInt64 { delta(\.metalGPUBusySkips) }
    var desktopDisplayLinkWakeups: UInt64 { delta(\.desktopDisplayLinkWakeups) }
    var desktopDisplayLinkTicks: UInt64 { delta(\.desktopDisplayLinkTicks) }
    var desktopDisplayLinkIdlePauses: UInt64 { delta(\.desktopDisplayLinkIdlePauses) }
    var cpuFallbackFrames: UInt64 { delta(\.cpuFallbackFrames) }

    var revisionSelectionToMetalCommit: SpiceLatencySummary {
        Self.clientSummary(latest.viewUpdateToMetalCommit)
    }
    var metalCommitToCompletion: SpiceLatencySummary {
        Self.clientSummary(latest.metalCommitToCompletion)
    }
    var metalRequestToPresented: SpiceLatencySummary {
        Self.clientSummary(latest.metalRequestToPresented)
    }

    var mjpegDecoderHandleCreations: UInt64 { delta(\.mjpegDecoderHandleCreations) }
    var mjpegDecodedFrames: UInt64 { delta(\.mjpegDecodedFrames) }
    var mjpegIOSurfaceFrames: UInt64 { delta(\.mjpegIOSurfaceFrames) }
    var mjpegDataFallbacks: UInt64 { delta(\.mjpegDataFallbacks) }
    var mjpegIOSurfaceAllocations: UInt64 { delta(\.mjpegIOSurfaceAllocations) }
    var mjpegPeakBuffersInUse: Int { latest.mjpegPeakBuffersInUse }
    var mjpegPeakConcurrentDecodes: Int { latest.mjpegPeakConcurrentDecodes }

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
        advancedVideoPresentedFrames != 0
            || nativeVideoFrames != 0
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

    var hasMJPEGActivity: Bool {
        mjpegDecoderHandleCreations != 0
            || mjpegDecodedFrames != 0
            || mjpegIOSurfaceFrames != 0
            || mjpegDataFallbacks != 0
            || mjpegIOSurfaceAllocations != 0
    }

    var summaryLines: [String] {
        var lines = [
            "swiftspice_display_channel_instances=\(latest.displayChannelCount)",
            "swiftspice_latest_sample_age_ms=\(stableSampleAgeMilliseconds)",
            "swiftspice_publisher_submissions_delta=\(publisherSubmissions)",
            "swiftspice_publisher_snapshot_attempts_delta=\(publisherSnapshotAttempts)",
            "swiftspice_publisher_emitted_frames_delta=\(publisherEmittedFrames)",
            "swiftspice_publisher_emitted_iosurface_frames_delta=\(publisherEmittedIOSurfaceFrames)",
            "swiftspice_publisher_emitted_cpu_only_frames_delta=\(publisherEmittedCPUOnlyFrames)",
            "swiftspice_publisher_stale_snapshots_delta=\(publisherStaleSnapshots)",
            "swiftspice_publisher_pending_evictions_delta=\(publisherPendingEvictions)",
            "swiftspice_publisher_demand_suppressed_submissions_delta=\(publisherDemandSuppressedSubmissions)",
            "swiftspice_publisher_pending_revision_coalesces_delta=\(publisherPendingRevisionCoalesces)",
            "swiftspice_publisher_prepared_frame_coalesces_delta=\(publisherPreparedFrameCoalesces)",
            "swiftspice_publisher_pending_surfaces_sample=\(publisherPendingSurfaces)",
            "swiftspice_publisher_demanded_surfaces_sample=\(publisherDemandedSurfaces)",
            "swiftspice_publisher_prepared_frames_sample=\(publisherPreparedFrames)",
            "swiftspice_desktop_delivered_snapshots_delta=\(desktopDeliveredSnapshots)",
            "swiftspice_desktop_stream_coalesces_delta=\(desktopStreamCoalesces)",
            "swiftspice_desktop_handler_deliveries_delta=\(desktopHandlerDeliveries)",
            "swiftspice_desktop_subscriptions_sample=\(desktopSubscriptions)",
            "swiftspice_desktop_visible_subscriptions_sample=\(desktopVisibleSubscriptions)",
            latencySummary(name: "swiftspice_framed_receive_batch_start_gap", value: publisherFramedReceiveBatchStartGap),
            latencySummary(name: "swiftspice_message_receive_to_surface_ready", value: publisherMessageReceiveToSurfaceReady),
            latencySummary(name: "swiftspice_surface_ready_to_publisher_submit", value: publisherSurfaceReadyToSubmit),
            latencySummary(name: "swiftspice_publisher_snapshot_duration", value: publisherSnapshotDuration),
            "swiftspice_revisioned_backing_observed=\(revisionedBackingEnabled)",
            "swiftspice_cpu_materializations_delta=\(cpuMaterializations)",
            "swiftspice_cpu_materialization_bytes_delta=\(cpuMaterializationBytes)",
            "swiftspice_pool_exhaustions_delta=\(poolExhaustions)",
            "swiftspice_in_flight_leases_observed_max=\(latest.inFlightLeases)",
            "swiftspice_gpu_errors_delta=\(gpuErrors)",
            "swiftspice_metal_presented_frames_delta=\(metalPresentedFrames)",
            "swiftspice_advanced_video_presented_frames_delta=\(advancedVideoPresentedFrames)",
            "swiftspice_metal_presentation_errors_delta=\(metalPresentationErrors)",
            "swiftspice_metal_frames_superseded_before_draw_delta=\(metalFramesSupersededBeforeDraw)",
            "swiftspice_metal_drawable_misses_delta=\(metalDrawableMisses)",
            "swiftspice_metal_command_creation_failures_delta=\(metalCommandCreationFailures)",
            "swiftspice_metal_command_buffers_committed_delta=\(metalCommandBuffersCommitted)",
            "swiftspice_metal_texture_cache_hits_delta=\(metalTextureCacheHits)",
            "swiftspice_metal_texture_cache_misses_delta=\(metalTextureCacheMisses)",
            "swiftspice_metal_texture_cache_evictions_delta=\(metalTextureCacheEvictions)",
            "swiftspice_metal_gpu_busy_skips_delta=\(metalGPUBusySkips)",
            "swiftspice_desktop_display_link_wakeups_delta=\(desktopDisplayLinkWakeups)",
            "swiftspice_desktop_display_link_ticks_delta=\(desktopDisplayLinkTicks)",
            "swiftspice_desktop_display_link_idle_pauses_delta=\(desktopDisplayLinkIdlePauses)",
            "swiftspice_cpu_fallback_frames_delta=\(cpuFallbackFrames)",
            latencySummary(
                name: "swiftspice_revision_selection_to_metal_commit",
                value: revisionSelectionToMetalCommit
            ),
            latencySummary(name: "swiftspice_metal_commit_to_completion", value: metalCommitToCompletion),
            latencySummary(name: "swiftspice_metal_request_to_presented", value: metalRequestToPresented),
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

        if hasMJPEGActivity {
            lines.append(contentsOf: [
                "swiftspice_mjpeg_decoder_handle_creations_delta=\(mjpegDecoderHandleCreations)",
                "swiftspice_mjpeg_decoded_frames_delta=\(mjpegDecodedFrames)",
                "swiftspice_mjpeg_iosurface_frames_delta=\(mjpegIOSurfaceFrames)",
                "swiftspice_mjpeg_data_fallbacks_delta=\(mjpegDataFallbacks)",
                "swiftspice_mjpeg_iosurface_allocations_delta=\(mjpegIOSurfaceAllocations)",
                "swiftspice_mjpeg_peak_buffers_in_use_sample=\(mjpegPeakBuffersInUse)",
                "swiftspice_mjpeg_peak_concurrent_decodes_sample=\(mjpegPeakConcurrentDecodes)",
            ])
        }

        return lines
    }

    private func delta(_ keyPath: KeyPath<SpiceSessionDiagnostics, UInt64>) -> UInt64 {
        counterDelta(latest[keyPath: keyPath], from: baseline[keyPath: keyPath])
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
