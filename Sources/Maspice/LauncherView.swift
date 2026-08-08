// SPDX-License-Identifier: MIT
import SwiftUI

struct LauncherView: View {
    let appDelegate: AppDelegate

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(ApplicationModel.self) private var applicationModel
    @AppStorage(Preferences.ravadaPortalURLKey) private var ravadaPortalURL = ""

    var body: some View {
        launcherContent
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
                    applicationModel.authorizePortalPresentation()
                    openWindow(id: "portal")
                    dismiss()
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

            if let summary = applicationModel.lastSessionDiagnosticsSummary {
                Button {
                    SessionDiagnosticsClipboard.copy(summary)
                } label: {
                    Label("Copy Last Diagnostics", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityHint("Copies only aggregate session counters and latency values.")
            }
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

    private func openSession(_ request: SessionRequest) {
        applicationModel.authorizeSessionPresentation(request)
        openWindow(value: request)
        dismiss()
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
