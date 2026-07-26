// SPDX-License-Identifier: MIT
import SwiftUI
import SpiceSessionLogic

struct SessionView: View {
    let appDelegate: AppDelegate

    @State private var model: SessionModel
    @State private var displayActions = SpiceDisplayActionRouter()
    @AppStorage(Preferences.shareClipboardKey) private var shareClipboard = true
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(ApplicationModel.self) private var applicationModel

    init(request: SessionRequest, appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        _model = State(initialValue: SessionModel(request: request))
    }

    var body: some View {
        ZStack {
            if model.client != nil {
                SpiceDisplayRepresentable(model: model, actionRouter: displayActions)
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
        .navigationTitle(model.windowTitle)
        .focusedSceneValue(\.sessionActions, focusedActions)
        .onAppear {
            model.setClipboardSharing(shareClipboard)
            model.start()
        }
        .onDisappear {
            model.stop()
        }
        .onChange(of: shareClipboard) {
            model.setClipboardSharing(shareClipboard)
        }
        .onChange(of: model.shouldReturnToLauncher, initial: true) {
            guard model.shouldReturnToLauncher else { return }
            if let message = model.terminalFailureMessage {
                applicationModel.presentSessionFailure(message)
            }
            openWindow(id: "launcher")
            dismiss()
        }
        .onChange(of: appDelegate.pendingRequests, initial: true) {
            for request in appDelegate.drainPendingRequests() {
                openWindow(value: request)
                dismissWindow(id: "launcher")
            }
        }
        .alert("USB Redirection", isPresented: usbErrorIsPresented) {
            Button("OK") { model.usbError = nil }
        } message: {
            Text(model.usbError ?? "Unknown USB error")
        }
    }

    private var focusedActions: FocusedSessionActions {
        FocusedSessionActions(
            availability: SessionCommandAvailability(
                hasActiveSession: model.client != nil,
                hasInput: model.isInputAvailable),
            sendCtrlAltDelete: displayActions.sendCtrlAltDelete,
            releaseCursor: displayActions.releaseCursor,
            usbDevices: model.usbDevices,
            toggleUSBDevice: model.toggleUSBDevice(id:))
    }

    private var usbErrorIsPresented: Binding<Bool> {
        Binding(
            get: { model.usbError != nil },
            set: { if !$0 { model.usbError = nil } })
    }
}
