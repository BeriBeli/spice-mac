// SPDX-License-Identifier: MIT
import SwiftUI
import Sparkle
import SpiceSessionLogic

@MainActor
struct FocusedSessionActions {
    let availability: SessionCommandAvailability
    let showsDiagnostics: Bool
    let sendCtrlAltDelete: () -> Void
    let releaseCursor: () -> Void
    let setDiagnosticsVisible: (Bool) -> Void
}

extension FocusedValues {
    @Entry var sessionActions: FocusedSessionActions?
}

struct SpiceCommands: Commands {
    let applicationModel: ApplicationModel
    let updater: SPUUpdater

    private var releaseNotesURL: URL {
        let version = Bundle.main.object(forInfoDictionaryKey: "MaspiceReleaseVersion") as? String
        let path = version.map { "tag/v\($0)" } ?? "latest"
        return URL(string: "https://github.com/BeriBeli/spice-mac/releases/\(path)")!
    }
    private let newIssueURL = URL(
        string: "https://github.com/BeriBeli/spice-mac/issues/new/choose")!

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @FocusedValue(\.sessionActions) private var sessionActions

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Maspice") {
                let version = Bundle.main.object(forInfoDictionaryKey: "MaspiceReleaseVersion") as? String
                    ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                    ?? ""
                NSApplication.shared.orderFrontStandardAboutPanel(options: [
                    .applicationVersion: version,
                ])
            }
        }

        CommandGroup(after: .appInfo) {
            CheckForUpdatesCommand(updater: updater)
        }

        CommandGroup(replacing: .newItem) {
            Button("Open Connection File…") {
                if let url = ConnectionFilePicker.chooseFile() {
                    let request = SessionRequest(url: url)
                    applicationModel.authorizeSessionPresentation(request)
                    openWindow(value: request)
                    dismissWindow(id: "main", value: MainWindowID.primary)
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
            Link("What's New", destination: releaseNotesURL)
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

            Divider()

            Toggle("Show Diagnostics", isOn: Binding(
                get: { sessionActions?.showsDiagnostics == true },
                set: { sessionActions?.setDiagnosticsVisible($0) }
            ))
            .keyboardShortcut("d", modifiers: [.control, .option])
            .disabled(sessionActions?.availability.hasActiveSession != true)
        }
    }
}
