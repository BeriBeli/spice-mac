// SPDX-License-Identifier: MIT
import Foundation
import SpiceController
import SwiftUI

struct SessionDiagnosticsRequest: Codable, Hashable {
    let sessionID: UUID
}

struct SessionDiagnosticsWindow: View {
    let request: SessionDiagnosticsRequest

    @Environment(ApplicationModel.self) private var applicationModel

    var body: some View {
        Group {
            if let presentation = applicationModel.sessionDiagnosticsPresentation(
                for: request.sessionID
            ) {
                SessionDiagnosticsMonitorView(
                    monitor: presentation.client.diagnosticsMonitor,
                    onCopy: {
                        applicationModel.copySessionDiagnosticsSummary(
                            for: request.sessionID
                        )
                    }
                )
                .navigationTitle(Text("Session Diagnostics — \(presentation.title)"))
            } else {
                ContentUnavailableView(
                    "Diagnostics Unavailable",
                    systemImage: "waveform.path.ecg",
                    description: Text("Return to an active SPICE session and reopen Diagnostics."))
            }
        }
        .frame(minWidth: 360, minHeight: 480)
        .onDisappear {
            applicationModel.dismissSessionDiagnostics(for: request.sessionID)
        }
    }
}

private struct SessionDiagnosticsMonitorView: View {
    @ObservedObject var monitor: SpiceClientDiagnosticsMonitor
    let onCopy: () -> Void

    var body: some View {
        SessionDiagnosticsView(snapshot: monitor.snapshot, onCopy: onCopy)
    }
}
