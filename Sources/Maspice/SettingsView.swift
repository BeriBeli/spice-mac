// SPDX-License-Identifier: MIT
import SwiftUI

struct SettingsView: View {
    @AppStorage(Preferences.shareClipboardKey) private var shareClipboard = true
    @AppStorage(Preferences.trashConnectionFileAfterUseKey) private var trashAfterUse = false
    @AppStorage(Preferences.ravadaPortalURLKey) private var ravadaPortalURL = ""

    var body: some View {
        Form {
            Section("Security") {
                Toggle("Share clipboard with virtual machines", isOn: $shareClipboard)
                Text("Disable clipboard sharing when connecting to an untrusted virtual machine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Move .vv files to Trash after connecting", isOn: $trashAfterUse)
                Text("Disabled by default. Enable only if you want connection files removed after use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Ravada Portal") {
                TextField("Portal URL", text: $ravadaPortalURL, prompt: Text("https://vdi.example.com/"))
                    .textContentType(.URL)
                Text("The portal handles credentials directly. Maspice only intercepts downloaded .vv connection files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Forget Saved Portal Certificate") {
                    if let portalHost {
                        Preferences.forgetPortalCertificateTrust(for: portalHost)
                    }
                }
                .disabled(portalHost == nil)
                Text("The current portal remains trusted until it is closed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 360)
        .scenePadding()
    }

    private var portalHost: String? {
        URL(string: ravadaPortalURL.trimmingCharacters(in: .whitespacesAndNewlines))?
            .host
    }
}
