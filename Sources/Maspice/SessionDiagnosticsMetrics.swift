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
