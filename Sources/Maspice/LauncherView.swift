// SPDX-License-Identifier: MIT
import SwiftUI

struct LauncherView: View {
    let appDelegate: AppDelegate

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(ApplicationModel.self) private var applicationModel
    @AppStorage(Preferences.ravadaPortalURLKey) private var ravadaPortalURL = ""
    @State private var isDropTargeted = false

    var body: some View {
        LauncherContent(
            portalURLText: $ravadaPortalURL,
            isDropTargeted: isDropTargeted,
            diagnosticsSummary: applicationModel.lastSessionDiagnosticsSummary,
            onOpenPortal: openPortal,
            onOpenFile: chooseAndOpen,
            onCopyDiagnostics: SessionDiagnosticsClipboard.copy)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: \.isFileURL), url.pathExtension.lowercased() == "vv" else { return false }
            openSession(SessionRequest(url: url))
            return true
        } isTargeted: {
            isDropTargeted = $0
        }
        .onChange(of: appDelegate.pendingRequests, initial: true) {
            routePendingRequests()
        }
        .alert("Remote Connection Failed", isPresented: sessionFailureIsPresented) {
            if portalURL != nil {
                Button("Open Portal") { applicationModel.clearSessionFailure(); openPortal() }
            }
            Button("Open Connection File…") { applicationModel.clearSessionFailure(); chooseAndOpen() }
            Button("Cancel", role: .cancel) { applicationModel.clearSessionFailure() }
        } message: {
            Text((applicationModel.sessionFailureMessage ?? "The connection could not be opened.") + "\nOpen the portal or a new connection file to reconnect.")
        }
    }

    private func openPortal() {
        applicationModel.showPortal()
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
        dismissWindow(id: "main", value: MainWindowID.primary)
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
    let isDropTargeted: Bool
    let diagnosticsSummary: String?
    let onOpenPortal: () -> Void
    let onOpenFile: () -> Void
    let onCopyDiagnostics: (String) -> Void
    @State private var draftPortalURL = ""
    @State private var isEditingAddress = false
    @FocusState private var addressIsFocused: Bool

    private var savedPortalURL: URL? {
        Preferences.ravadaPortalURL(from: portalURLText)
    }

    private var draftURL: URL? {
        Preferences.ravadaPortalURL(from: draftPortalURL)
    }

    private var showsAddressEditor: Bool {
        isEditingAddress || savedPortalURL == nil
    }

    var body: some View {
        VStack(spacing: 18) {
            LauncherHeader()

            if let savedPortalURL, !isEditingAddress {
                Text(savedPortalURL.absoluteString)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help("\(savedPortalURL.absoluteString)\nDouble-click to edit.")
                    .frame(maxWidth: 380)
                    .highPriorityGesture(TapGesture(count: 2).onEnded { beginEditingAddress() })
                    .accessibilityAction(named: Text("Edit Address")) { beginEditingAddress() }
            } else {
                TextField(
                    "Ravada portal URL",
                    text: $draftPortalURL,
                    prompt: Text("https://vdi.example.com/")
                )
                .textContentType(.URL)
                .frame(maxWidth: 380)
                .focused($addressIsFocused)
                .onAppear { if isEditingAddress { addressIsFocused = true } }
                .onSubmit {
                    if isEditingAddress { _ = saveAddress() } else { openPortal() }
                }
                .onExitCommand(perform: cancelEditingAddress)
            }

            LauncherActions(
                canOpenPortal: showsAddressEditor ? draftURL != nil : savedPortalURL != nil,
                onOpenPortal: openPortal,
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
        .onChange(of: portalURLText, initial: true) {
            draftPortalURL = portalURLText
            isEditingAddress = false
        }
    }

    private func beginEditingAddress() {
        draftPortalURL = portalURLText
        isEditingAddress = true
    }

    private func cancelEditingAddress() {
        draftPortalURL = portalURLText
        isEditingAddress = false
        addressIsFocused = false
    }

    private func saveAddress() -> Bool {
        guard let draftURL else { return false }
        portalURLText = draftURL.absoluteString
        isEditingAddress = false
        addressIsFocused = false
        return true
    }

    private func openPortal() {
        if showsAddressEditor, !saveAddress() { return }
        onOpenPortal()
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
