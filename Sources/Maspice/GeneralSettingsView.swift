// SPDX-License-Identifier: MIT
import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(Preferences.shareClipboardKey) private var shareClipboard = true
    @AppStorage(Preferences.trashConnectionFileAfterUseKey) private var trashAfterUse = false

    var body: some View {
        Form {
            Section("Virtual Machine") {
                SettingsPreferenceRow(
                    title: "Share clipboard",
                    description: "Allow text to be copied between this Mac and the virtual machine.",
                    isOn: $shareClipboard)
            }

            Section("Connection Files") {
                SettingsPreferenceRow(
                    title: "Move .vv files to Trash after connecting",
                    description: "User-supplied files are preserved by default.",
                    isOn: $trashAfterUse)
            }
        }
        .formStyle(.grouped)
        .scenePadding()
    }
}

struct SettingsPreferenceRow: View {
    let title: LocalizedStringResource
    let description: LocalizedStringResource
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: $isOn)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
