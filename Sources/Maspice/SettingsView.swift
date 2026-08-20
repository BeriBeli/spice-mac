// SPDX-License-Identifier: MIT
import Sparkle
import SwiftUI

struct SettingsView: View {
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
    }

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            UpdateSettingsView(updater: updater)
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }

            PortalSettingsView()
                .tabItem {
                    Label("Portal", systemImage: "globe")
                }
        }
        .frame(width: 520, height: 360)
    }
}
