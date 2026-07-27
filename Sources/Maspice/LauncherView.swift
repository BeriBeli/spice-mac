// SPDX-License-Identifier: MIT
import SwiftUI

struct LauncherView: View {
    let appDelegate: AppDelegate

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(ApplicationModel.self) private var applicationModel
    @AppStorage(Preferences.ravadaPortalURLKey) private var ravadaPortalURL = ""
    @State private var showsPortal = false

    var body: some View {
        Group {
            if showsPortal, let portalURL {
                portalContent(url: portalURL)
            } else {
                launcherContent
            }
        }
        .onChange(of: appDelegate.pendingRequests, initial: true) {
            routePendingRequests()
        }
        .alert("Connection Failed", isPresented: sessionFailureIsPresented) {
            Button("OK") { applicationModel.clearSessionFailure() }
        } message: {
            Text(applicationModel.sessionFailureMessage ?? "The connection could not be opened.")
        }
    }

    private var launcherContent: some View {
        VStack(spacing: 18) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Maspice")
                .font(.title.bold())

            Text("Connect to a SPICE console.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            TextField("Ravada portal URL", text: $ravadaPortalURL, prompt: Text("https://vdi.example.com/"))
                .textContentType(.URL)
                .frame(maxWidth: 380)

            VStack(spacing: 12) {
                Button {
                    showsPortal = true
                } label: {
                    Text("Open Ravada Portal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(portalURL == nil)

                Button {
                    chooseAndOpen()
                } label: {
                    Text("Open Connection File…")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            .controlSize(.large)
            .frame(width: 240)
        }
        .padding(32)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in openSession(SessionRequest(url: url)) }
            }
            return true
        }
    }

    private func portalContent(url: URL) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button("Back to Launcher", systemImage: "chevron.left") {
                    showsPortal = false
                }
                Spacer()
                Text(url.host() ?? url.absoluteString)
                    .foregroundStyle(.secondary)
            }
            .padding(10)

            Divider()

            RavadaPortalView(
                url: url,
                onConnectionFile: openDownloadedConnection,
                onError: applicationModel.presentSessionFailure)
        }
        .frame(minWidth: 900, minHeight: 650)
    }

    private func routePendingRequests() {
        let requests = appDelegate.drainPendingRequests()
        for request in requests {
            openSession(request)
        }
    }

    private func chooseAndOpen() {
        if let url = ConnectionFilePicker.chooseFile() {
            openSession(SessionRequest(url: url))
        }
    }

    private func openDownloadedConnection(_ url: URL) {
        showsPortal = false
        openSession(SessionRequest(url: url, removesFileAfterStart: true))
    }

    private func openSession(_ request: SessionRequest) {
        openWindow(value: request)
        dismissWindow(id: "launcher")
    }

    private var portalURL: URL? {
        let value = ravadaPortalURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host != nil,
              components.user == nil,
              components.password == nil else { return nil }
        components.scheme = "https"
        if scheme == "http", components.port == 80 {
            components.port = nil
        }
        return components.url
    }

    private var sessionFailureIsPresented: Binding<Bool> {
        Binding(
            get: { applicationModel.sessionFailureMessage != nil },
            set: { if !$0 { applicationModel.clearSessionFailure() } })
    }
}
