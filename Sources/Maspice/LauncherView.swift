// SPDX-License-Identifier: MIT
import SwiftUI

struct LauncherView: View {
    let appDelegate: AppDelegate

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(ApplicationModel.self) private var applicationModel
    @AppStorage(Preferences.ravadaPortalURLKey) private var ravadaPortalURL = ""
    @State private var isDropTargeted = false

    var body: some View {
        LauncherContent(
            portalURLText: $ravadaPortalURL,
            canOpenPortal: portalURL != nil,
            isDropTargeted: isDropTargeted,
            diagnosticsSummary: applicationModel.lastSessionDiagnosticsSummary,
            onOpenPortal: openPortal,
            onOpenFile: chooseAndOpen,
            onCopyDiagnostics: SessionDiagnosticsClipboard.copy)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: \.isFileURL) else { return false }
            openSession(SessionRequest(url: url))
            return true
        } isTargeted: {
            isDropTargeted = $0
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

    private func openPortal() {
        applicationModel.authorizePortalPresentation()
        openWindow(id: "portal")
        dismiss()
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

private struct LauncherContent: View {
    @Binding var portalURLText: String
    let canOpenPortal: Bool
    let isDropTargeted: Bool
    let diagnosticsSummary: String?
    let onOpenPortal: () -> Void
    let onOpenFile: () -> Void
    let onCopyDiagnostics: (String) -> Void

    var body: some View {
        VStack(spacing: 18) {
            LauncherHeader()

            TextField(
                "Ravada portal URL",
                text: $portalURLText,
                prompt: Text("https://vdi.example.com/")
            )
            .textContentType(.URL)
            .frame(maxWidth: 380)

            LauncherActions(
                canOpenPortal: canOpenPortal,
                onOpenPortal: onOpenPortal,
                onOpenFile: onOpenFile)

            if let diagnosticsSummary {
                Button {
                    onCopyDiagnostics(diagnosticsSummary)
                } label: {
                    Label("Copy Last Diagnostics", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityHint("Copies only aggregate session counters and latency values.")
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(isDropTargeted ? 0.08 : 0))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(isDropTargeted ? 1 : 0), lineWidth: 2)
        }
    }
}

private struct LauncherHeader: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Maspice")
                .font(.title.bold())

            Text("Connect to a SPICE console.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
    }
}

private struct LauncherActions: View {
    let canOpenPortal: Bool
    let onOpenPortal: () -> Void
    let onOpenFile: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: onOpenPortal) {
                Text("Open Ravada Portal")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canOpenPortal)

            Button(action: onOpenFile) {
                Text("Open Connection File…")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut("o", modifiers: .command)
        }
        .controlSize(.large)
        .frame(width: 240)
    }
}
