// SPDX-License-Identifier: MIT
import SwiftUI

struct RavadaPortalWindow: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(ApplicationModel.self) private var applicationModel
    @AppStorage(Preferences.ravadaPortalURLKey) private var ravadaPortalURL = ""
    @State private var isHandingOffConnection = false

    var body: some View {
        Group {
            if let portalURL {
                portalContent(url: portalURL)
            } else {
                ContentUnavailableView(
                    "No Ravada Portal",
                    systemImage: "globe.badge.chevron.backward",
                    description: Text("Return to the launcher and enter a valid portal URL."))
            }
        }
        .frame(minWidth: 900, minHeight: 650)
        .navigationTitle("Ravada Portal")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Back to Launcher", systemImage: "house") {
                    returnToLauncher()
                }
                .help("Close the portal and return to the launcher")
            }
        }
        .onAppear {
            guard applicationModel.activatePortalPresentation() else {
                openWindow(id: "launcher")
                dismiss()
                return
            }
        }
        .onDisappear {
            applicationModel.deactivatePortalPresentation()
        }
        .alert("Connection Failed", isPresented: sessionFailureIsPresented) {
            Button("OK") { applicationModel.clearSessionFailure() }
        } message: {
            Text(applicationModel.sessionFailureMessage ?? "The connection could not be opened.")
        }
    }

    private func portalContent(url: URL) -> some View {
        RavadaPortalView(
            url: url,
            onConnectionFile: openDownloadedConnection,
            onError: presentPortalError)
    }

    private func returnToLauncher() {
        openWindow(id: "launcher")
        dismiss()
    }

    private func openDownloadedConnection(_ url: URL) {
        guard !isHandingOffConnection else { return }
        isHandingOffConnection = true
        let request = SessionRequest(url: url, removesFileAfterStart: true)
        applicationModel.authorizeSessionPresentation(request)
        openWindow(value: request)
        dismiss()
    }

    private func presentPortalError(_ message: String) {
        guard !isHandingOffConnection else { return }
        applicationModel.presentSessionFailure(message)
    }

    private var portalURL: URL? {
        Preferences.ravadaPortalURL(from: ravadaPortalURL)
    }

    private var sessionFailureIsPresented: Binding<Bool> {
        Binding(
            get: { applicationModel.sessionFailureMessage != nil },
            set: { if !$0 { applicationModel.clearSessionFailure() } })
    }
}
