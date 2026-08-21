// SPDX-License-Identifier: MIT
import SwiftUI

enum MainWindowID: String, Codable, Hashable {
    case primary
}

struct MainWindowRoot: View {
    let appDelegate: AppDelegate

    @Environment(ApplicationModel.self) private var applicationModel

    var body: some View {
        content
            .background {
                MainWindowPresentationBridge(
                    destination: applicationModel.mainDestination
                )
                .frame(width: 0, height: 0)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch applicationModel.mainDestination {
        case .launcher:
            LauncherView(appDelegate: appDelegate)
        case .portal:
            RavadaPortalWindow()
        }
    }
}
