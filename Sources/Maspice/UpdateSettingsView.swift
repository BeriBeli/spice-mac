// SPDX-License-Identifier: MIT
import Sparkle
import SwiftUI

struct UpdateSettingsView: View {
    private let updater: SPUUpdater
    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool

    init(updater: SPUUpdater) {
        self.updater = updater
        _automaticallyChecksForUpdates = State(
            initialValue: updater.automaticallyChecksForUpdates)
        _automaticallyDownloadsUpdates = State(
            initialValue: updater.automaticallyDownloadsUpdates)
    }

    var body: some View {
        Form {
            Section("Automatic Updates") {
                SettingsPreferenceRow(
                    title: "Automatically check for updates",
                    description: "Maspice checks for new releases once a day.",
                    isOn: $automaticallyChecksForUpdates)
                    .onChange(of: automaticallyChecksForUpdates) {
                        updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
                    }

                SettingsPreferenceRow(
                    title: "Download updates automatically",
                    description: "Install downloaded updates the next time Maspice quits.",
                    isOn: $automaticallyDownloadsUpdates)
                    .disabled(!automaticallyChecksForUpdates)
                    .onChange(of: automaticallyDownloadsUpdates) {
                        updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
                    }
            }
        }
        .formStyle(.grouped)
        .scenePadding()
    }
}
