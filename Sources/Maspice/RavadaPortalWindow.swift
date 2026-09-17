// SPDX-License-Identifier: MIT
import SwiftUI

struct RavadaPortalWindow: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(ApplicationModel.self) private var applicationModel
    @AppStorage(Preferences.ravadaPortalURLKey) private var ravadaPortalURL = ""
    @State private var isHandingOffConnection = false
    @State private var portalError: String?

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
        .frame(minWidth: 640, minHeight: 480)
        .navigationTitle("Ravada Portal")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Back to Launcher", systemImage: "house") {
                    returnToLauncher()
                }
                .help("Close the portal and return to the launcher")
            }
        }
        .alert("Portal Action Failed", isPresented: Binding(
            get: { portalError != nil }, set: { if !$0 { portalError = nil } })) {
            Button("OK") { portalError = nil }
        } message: {
            Text(portalError ?? "The portal action could not be completed.")
        }
    }

    private func portalContent(url: URL) -> some View {
        RavadaPortalView(
            url: url,
            onConnectionFile: openDownloadedConnection,
            onError: presentPortalError)
    }

    private func returnToLauncher() {
        applicationModel.showLauncher()
    }

    private func openDownloadedConnection(_ url: URL) {
        guard !isHandingOffConnection else { return }
        isHandingOffConnection = true
        let request = SessionRequest(url: url, removesFileAfterStart: true)
        applicationModel.authorizeSessionPresentation(request)
        openWindow(value: request)
        dismissWindow(id: "main", value: MainWindowID.primary)
        applicationModel.showLauncher()
    }

    private func presentPortalError(_ message: String) {
        guard !isHandingOffConnection else { return }
        portalError = message
    }

    private var portalURL: URL? {
        Preferences.ravadaPortalURL(from: ravadaPortalURL)
    }

}
