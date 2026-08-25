// SPDX-License-Identifier: MIT
import SpiceController
import SwiftUI

struct SessionDiagnosticsView: View {
    let snapshot: SpiceClientDiagnosticsSnapshot
    let onCopy: () -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            SessionDiagnosticsContent(snapshot: snapshot, onCopy: onCopy)
            ScrollView {
                SessionDiagnosticsContent(snapshot: snapshot, onCopy: onCopy)
            }
            .scrollIndicators(.visible)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct SessionDiagnosticsContent: View {
    let snapshot: SpiceClientDiagnosticsSnapshot
    let onCopy: () -> Void

    var body: some View {
        let swiftSpiceMetrics = snapshot.swiftSpiceDiagnostics.map(
            SessionDiagnosticsSwiftSpiceMetrics.init
        )

        VStack(alignment: .leading, spacing: 8) {
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
            SessionDiagnosticsDisplaySection(metrics: swiftSpiceMetrics)
            Divider()
            SessionDiagnosticsRendererSection(
                metrics: swiftSpiceMetrics,
                codecFallbackReconnects: snapshot.videoCodecFallbackReconnects
            )
            if let swiftSpiceMetrics,
               swiftSpiceMetrics.hasAdvancedVideoActivity || swiftSpiceMetrics.hasMJPEGActivity {
                Divider()
                SessionDiagnosticsVideoCodecSection(metrics: swiftSpiceMetrics)
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
