// SPDX-License-Identifier: MIT
import Sparkle
import SwiftUI

@main
struct MaspiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var applicationModel = ApplicationModel()
    // SPUUpdater holds its delegate weakly; retain it for the app's lifetime.
    private let updaterDelegate: UpdateChannelDelegate
    private let updaterController: SPUStandardUpdaterController

    init() {
        let delegate = UpdateChannelDelegate()
        updaterDelegate = delegate
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: delegate,
            userDriverDelegate: nil)
        // Prefer the feed shipped in Info.plist over a legacy defaults override.
        updaterController.updater.clearFeedURLFromUserDefaults()
        updaterController.startUpdater()
    }

    var body: some Scene {
        WindowGroup("Maspice", id: "main", for: MainWindowID.self) { _ in
            MainWindowRoot(appDelegate: appDelegate)
                .environment(applicationModel)
        } defaultValue: {
            .primary
        }
        .defaultSize(width: 520, height: 300)
        .windowIdealSize(.maximum)
        .restorationBehavior(.disabled)
        .commandsRemoved()

        WindowGroup("SPICE Console", for: SessionRequest.self) { request in
            if let request = request.wrappedValue {
                SessionView(request: request, appDelegate: appDelegate)
                    .environment(applicationModel)
            } else {
                ContentUnavailableView(
                    "No Connection",
                    systemImage: "display.trianglebadge.exclamationmark",
                    description: Text("Open a direct SPICE .vv file."))
            }
        }
        .defaultWindowPlacement { _, context in
            let available = context.defaultDisplay.visibleRect.size
            return WindowPlacement(size: CGSize(
                width: min(1024, available.width * 0.9),
                height: min(768, available.height * 0.9)
            ))
        }
        .windowIdealSize(.maximum)
        .restorationBehavior(.disabled)
        .commands {
            SpiceCommands(
                applicationModel: applicationModel,
                updater: updaterController.updater)
        }

        WindowGroup("Session Diagnostics", for: SessionDiagnosticsRequest.self) { request in
            if let request = request.wrappedValue {
                SessionDiagnosticsWindow(request: request)
                    .environment(applicationModel)
            } else {
                ContentUnavailableView(
                    "No Session Diagnostics",
                    systemImage: "waveform.path.ecg",
                    description: Text("Open Diagnostics from an active SPICE session."))
            }
        }
        .defaultSize(width: 420, height: 720)
        .windowManagerRole(.principal)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView(updater: updaterController.updater)
        }
    }
}
