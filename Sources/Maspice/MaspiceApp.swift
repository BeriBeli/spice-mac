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
        .defaultSize(width: 1024, height: 768)
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
        .defaultSize(width: 1024, height: 768)
        .windowIdealSize(.maximum)
        .restorationBehavior(.disabled)
        .commands {
            SpiceCommands(
                applicationModel: applicationModel,
                updater: updaterController.updater)
        }

        Settings {
            SettingsView(updater: updaterController.updater)
        }
    }
}
