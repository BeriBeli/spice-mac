// SPDX-License-Identifier: MIT
import SwiftUI
import SpiceSessionLogic

@MainActor
struct FocusedSessionActions {
    let availability: SessionCommandAvailability
    let sendCtrlAltDelete: () -> Void
    let releaseCursor: () -> Void
}

private struct FocusedSessionActionsKey: FocusedValueKey {
    typealias Value = FocusedSessionActions
}

extension FocusedValues {
    var sessionActions: FocusedSessionActions? {
        get { self[FocusedSessionActionsKey.self] }
        set { self[FocusedSessionActionsKey.self] = newValue }
    }
}

struct SpiceCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @FocusedValue(\.sessionActions) private var sessionActions
    @AppStorage(Preferences.shareClipboardKey) private var shareClipboard = true

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…") {
                if let url = ConnectionFilePicker.chooseFile() {
                    openWindow(value: SessionRequest(url: url))
                    dismissWindow(id: "launcher")
                }
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandMenu("Connection") {
            Button("Send Ctrl-Alt-Del") {
                sessionActions?.sendCtrlAltDelete()
            }
            .disabled(sessionActions?.availability.canSendCtrlAltDelete != true)

            Button("Release Cursor") {
                sessionActions?.releaseCursor()
            }
            .keyboardShortcut("r", modifiers: [.control, .option])
            .disabled(sessionActions?.availability.canReleaseCursor != true)

            Divider()

            Toggle("Share Clipboard with VM", isOn: $shareClipboard)

        }
    }
}
