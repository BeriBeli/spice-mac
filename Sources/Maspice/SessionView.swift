// SPDX-License-Identifier: MIT
import SwiftUI
import SpiceSessionLogic

struct SessionView: View {
    let appDelegate: AppDelegate
    let requestID: UUID

    @State private var model: SessionModel
    @State private var isReturningToLauncher = false
    @AppStorage(Preferences.shareClipboardKey) private var shareClipboard = true
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismiss) private var dismiss
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
            InitialWindowZoomBridge()
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
            model.setClipboardSharing(shareClipboard)
            model.start()
            if model.shouldReturnToLauncher {
                returnToLauncher()
            }
        }
        .onDisappear {
            applicationModel.deactivateSessionPresentation(for: requestID)
            model.stop()
        }
        .onChange(of: shareClipboard) {
            model.setClipboardSharing(shareClipboard)
        }
        .onChange(of: model.shouldReturnToLauncher, initial: true) {
            guard applicationModel.isSessionPresentationActive(for: requestID),
                  model.shouldReturnToLauncher else { return }
            returnToLauncher()
        }
        .onChange(of: appDelegate.pendingRequests, initial: true) {
            for request in appDelegate.drainPendingRequests() {
                applicationModel.authorizeSessionPresentation(request)
                openWindow(value: request)
                dismissWindow(id: "launcher")
            }
        }
    }

    private var focusedActions: FocusedSessionActions {
        FocusedSessionActions(
            availability: SessionCommandAvailability(
                hasActiveSession: model.client != nil,
                hasInput: model.isInputAvailable),
            sendCtrlAltDelete: model.sendCtrlAltDelete,
            releaseCursor: model.releaseAllInput)
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
