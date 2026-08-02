// SPDX-License-Identifier: MIT
import SwiftUI
import Sparkle
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
    let applicationModel: ApplicationModel
    let updater: SPUUpdater

    private let latestReleaseURL = URL(
        string: "https://github.com/BeriBeli/spice-mac/releases/latest")!
    private let newIssueURL = URL(
        string: "https://github.com/BeriBeli/spice-mac/issues/new/choose")!

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @FocusedValue(\.sessionActions) private var sessionActions

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesCommand(updater: updater)
        }

        CommandGroup(replacing: .newItem) {
            Button("Open Connection File…") {
                if let url = ConnectionFilePicker.chooseFile() {
                    let request = SessionRequest(url: url)
                    applicationModel.authorizeSessionPresentation(request)
                    openWindow(value: request)
                    dismissWindow(id: "launcher")
                }
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {}
        CommandGroup(replacing: .importExport) {}
        CommandGroup(replacing: .printItem) {}
        CommandGroup(replacing: .textFormatting) {}
        CommandGroup(replacing: .toolbar) {}
        CommandGroup(replacing: .sidebar) {}
        CommandGroup(replacing: .help) {
            Link("What's New", destination: latestReleaseURL)
            Link("Report an Issue…", destination: newIssueURL)
        }

        CommandMenu("Session") {
            Button("Send Ctrl-Alt-Delete") {
                sessionActions?.sendCtrlAltDelete()
            }
            .disabled(sessionActions?.availability.canSendCtrlAltDelete != true)

            Button("Release Pointer") {
                sessionActions?.releaseCursor()
            }
            .keyboardShortcut("r", modifiers: [.control, .option])
            .disabled(sessionActions?.availability.canReleaseCursor != true)
        }
    }
}
