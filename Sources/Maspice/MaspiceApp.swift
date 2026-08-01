// SPDX-License-Identifier: MIT
import SwiftUI

@main
struct MaspiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var applicationModel = ApplicationModel()

    var body: some Scene {
        Window("Maspice", id: "launcher") {
            LauncherView(appDelegate: appDelegate)
                .environment(applicationModel)
        }
        .defaultSize(width: 520, height: 300)

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
        .restorationBehavior(.disabled)
        .commands {
            SpiceCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
