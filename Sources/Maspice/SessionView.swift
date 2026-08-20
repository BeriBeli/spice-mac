// SPDX-License-Identifier: MIT
import SpiceController
import SwiftUI
import SpiceSessionLogic

struct SessionView: View {
    let appDelegate: AppDelegate
    let requestID: UUID

    @State private var model: SessionModel
    @State private var isReturningToLauncher = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(ApplicationModel.self) private var applicationModel

    init(request: SessionRequest, appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        requestID = request.id
        _model = State(initialValue: SessionModel(request: request))
    }

    var body: some View {
        ZStack {
            if let client = model.client {
                SwiftSpiceDesktop(client: client, model: model)
            } else {
                Color.clear
            }

            if let message = model.statusMessage {
                ContentUnavailableView {
                    Label("SPICE Console", systemImage: "display.trianglebadge.exclamationmark")
                } description: {
                    Text(message)
                        .multilineTextAlignment(.center)
                }
                .padding(40)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .background {
            SessionChangeObserver(
                appDelegate: appDelegate,
                requestID: requestID,
                model: model,
                onReturnToLauncher: returnToLauncher)
                .frame(width: 0, height: 0)
        }
        .navigationTitle(model.windowTitle)
        .focusedSceneValue(\.sessionActions, focusedActions)
        .onAppear {
            guard applicationModel.activateSessionPresentation(for: requestID) else {
                openWindow(id: "launcher")
                dismiss()
                return
            }
            model.start()
            if model.shouldReturnToLauncher {
                returnToLauncher()
            }
        }
        .onDisappear {
            setDiagnosticsVisible(false)
            applicationModel.deactivateSessionPresentation(for: requestID)
            model.stop()
        }
    }

    private var focusedActions: FocusedSessionActions {
        FocusedSessionActions(
            availability: SessionCommandAvailability(
                hasActiveSession: model.client != nil,
                hasInput: model.isInputAvailable),
            showsDiagnostics: showsDiagnostics,
            sendCtrlAltDelete: model.sendCtrlAltDelete,
            releaseCursor: model.releaseAllInput,
            setDiagnosticsVisible: setDiagnosticsVisible)
    }

    private var showsDiagnostics: Bool {
        applicationModel.isSessionDiagnosticsPresented(for: requestID)
    }

    private var diagnosticsRequest: SessionDiagnosticsRequest {
        SessionDiagnosticsRequest(sessionID: requestID)
    }

    private func setDiagnosticsVisible(_ visible: Bool) {
        guard showsDiagnostics != visible else { return }
        if visible {
            guard let client = model.client else { return }
            applicationModel.presentSessionDiagnostics(
                for: requestID,
                title: model.baseTitle,
                client: client
            )
            openWindow(value: diagnosticsRequest)
        } else {
            dismissWindow(value: diagnosticsRequest)
            applicationModel.dismissSessionDiagnostics(for: requestID)
        }
    }

    private func returnToLauncher() {
        guard !isReturningToLauncher else { return }
        isReturningToLauncher = true
        if let message = model.terminalFailureMessage {
            applicationModel.presentSessionFailure(message)
        }
        openWindow(id: "launcher")
        dismiss()
    }
}

private struct SessionChangeObserver: View {
    let appDelegate: AppDelegate
    let requestID: UUID
    let model: SessionModel
    let onReturnToLauncher: @MainActor () -> Void

    @AppStorage(Preferences.shareClipboardKey) private var shareClipboard = true
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(ApplicationModel.self) private var applicationModel

    var body: some View {
        Color.clear
            .onChange(of: shareClipboard, initial: true) {
                model.setClipboardSharing(shareClipboard)
            }
            .onChange(of: model.shouldReturnToLauncher, initial: true) {
                guard applicationModel.isSessionPresentationActive(for: requestID),
                      model.shouldReturnToLauncher else { return }
                onReturnToLauncher()
            }
            .onChange(of: appDelegate.pendingRequests, initial: true) {
                for request in appDelegate.drainPendingRequests() {
                    applicationModel.authorizeSessionPresentation(request)
                    openWindow(value: request)
                    dismissWindow(id: "launcher")
                }
            }
    }
}
