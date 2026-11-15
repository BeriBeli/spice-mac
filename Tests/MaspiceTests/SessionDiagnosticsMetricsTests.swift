// SPDX-License-Identifier: MIT
import SpiceController
import Testing
@testable import Maspice
@testable import SwiftSpice

@Suite("Visible session diagnostics")
struct SessionDiagnosticsMetricsTests {
    @Test func activeDisplayExportsZeroVideoActivity() {
        var sample = SpiceSessionDiagnostics.empty
        sample.displayChannelCount = 1
        let metrics = SessionDiagnosticsSwiftSpiceMetrics(.init(
            baseline: sample, latest: sample
        ))
        #expect(metrics.summaryLines.contains("swiftspice_display_stream_create_messages_delta=0"))
        #expect(metrics.summaryLines.contains("swiftspice_vt_decoded_frames_delta=0"))
        #expect(metrics.summaryLines.contains("swiftspice_mjpeg_decoded_frames_delta=0"))
        #expect(metrics.gpuCopyMeanWaitMilliseconds == nil)
    }

    @Test func copyWaitUsesCollectionWindowAndRebasesResetCounters() {
        var baseline = SpiceSessionDiagnostics.empty
        baseline.gpuCopyBytes = 1_000
        baseline.gpuCopySynchronizationCount = 10
        baseline.gpuCopySynchronizationNanoseconds = 10_000_000
        var latest = baseline
        latest.gpuCopyBytes = 1_800
        latest.gpuCopySynchronizationCount = 12
        latest.gpuCopySynchronizationNanoseconds = 14_000_000
        let metrics = SessionDiagnosticsSwiftSpiceMetrics(.init(
            baseline: baseline, latest: latest
        ))
        #expect(metrics.gpuCopyBytes == 800)
        #expect(metrics.gpuCopySynchronizationCount == 2)
        #expect(metrics.gpuCopyWaitMilliseconds == 4)
        #expect(metrics.gpuCopyMeanWaitMilliseconds == 2)

        latest.gpuCopyBytes = 400
        latest.gpuCopySynchronizationCount = 1
        latest.gpuCopySynchronizationNanoseconds = 2_000_000
        let reset = SessionDiagnosticsSwiftSpiceMetrics(.init(
            baseline: baseline, latest: latest
        ))
        #expect(reset.gpuCopyBytes == 400)
        #expect(reset.gpuCopySynchronizationCount == 1)
        #expect(reset.gpuCopyMeanWaitMilliseconds == 2)
    }
}
