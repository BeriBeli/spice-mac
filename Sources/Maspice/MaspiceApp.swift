// SPDX-License-Identifier: MIT
import Sparkle
import SwiftUI

@main
struct MaspiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var applicationModel = ApplicationModel()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil)

    var body: some Scene {
        Window("Maspice", id: "launcher") {
            LauncherView(appDelegate: appDelegate)
                .environment(applicationModel)
        }
        .defaultSize(width: 520, height: 300)
        .restorationBehavior(.disabled)

        Window("Ravada Portal", id: "portal") {
            RavadaPortalWindow()
                .environment(applicationModel)
        }
        .defaultWindowPlacement { _, context in
            WindowPlacement(size: context.defaultDisplay.visibleRect.size)
        }
        .windowIdealSize(.maximum)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

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
            WindowPlacement(size: context.defaultDisplay.visibleRect.size)
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
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView(updater: updaterController.updater)
        }
    }
}
