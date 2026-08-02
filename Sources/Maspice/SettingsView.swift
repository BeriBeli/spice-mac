// SPDX-License-Identifier: MIT
import Sparkle
import SwiftUI

struct SettingsView: View {
    private let updater: SPUUpdater

    @AppStorage(Preferences.shareClipboardKey) private var shareClipboard = true
    @AppStorage(Preferences.trashConnectionFileAfterUseKey) private var trashAfterUse = false
    @AppStorage(Preferences.ravadaPortalURLKey) private var ravadaPortalURL = ""
    @State private var savedCertificateHost: String?
    @State private var forgottenCertificateHost: String?
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
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            updateSettings
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }

            portalSettings
                .tabItem {
                    Label("Portal", systemImage: "globe")
                }
        }
        .frame(width: 520, height: 360)
        .task {
            refreshCertificateStatus()
        }
        .onChange(of: ravadaPortalURL) {
            forgottenCertificateHost = nil
            refreshCertificateStatus()
        }
    }

    private var generalSettings: some View {
        Form {
            Section("Virtual Machine") {
                preferenceRow(
                    title: "Share clipboard",
                    description: "Allow text to be copied between this Mac and the virtual machine.",
                    isOn: $shareClipboard)
            }

            Section("Connection Files") {
                preferenceRow(
                    title: "Move .vv files to Trash after connecting",
                    description: "User-supplied files are preserved by default.",
                    isOn: $trashAfterUse)
            }
        }
        .formStyle(.grouped)
        .scenePadding()
    }

    private var updateSettings: some View {
        Form {
            Section("Automatic Updates") {
                preferenceRow(
                    title: "Automatically check for updates",
                    description: "Maspice checks for new releases once a day.",
                    isOn: $automaticallyChecksForUpdates)
                    .onChange(of: automaticallyChecksForUpdates) {
                        updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
                    }

                preferenceRow(
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

    private var portalSettings: some View {
        Form {
            Section("Ravada Portal") {
                TextField("Portal URL", text: $ravadaPortalURL, prompt: Text("https://vdi.example.com/"))
                    .textContentType(.URL)

                if !trimmedPortalURL.isEmpty, portalURL == nil {
                    Text("Enter a valid HTTP or HTTPS portal URL.")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("Maspice keeps portal credentials in the embedded browser and only handles downloaded .vv files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Certificate") {
                certificateSettings
            }
        }
        .formStyle(.grouped)
        .scenePadding()
    }

    @ViewBuilder
    private var certificateSettings: some View {
        if let portalHost, savedCertificateHost == portalHost {
            LabeledContent("Saved for") {
                Text(portalHost)
                    .foregroundStyle(.secondary)
            }

            Button("Forget Saved Certificate") {
                Preferences.forgetPortalCertificateTrust(for: portalHost)
                savedCertificateHost = nil
                forgottenCertificateHost = portalHost
            }
        } else if let portalHost, forgottenCertificateHost == portalHost {
            Label("Saved certificate removed", systemImage: "checkmark.circle")
            Text("An open portal window remains trusted until it is closed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("No saved certificate for this portal.")
                .foregroundStyle(.secondary)
        }
    }

    private func preferenceRow(
        title: String,
        description: String,
        isOn: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: isOn)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var trimmedPortalURL: String {
        ravadaPortalURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var portalURL: URL? {
        Preferences.ravadaPortalURL(from: ravadaPortalURL)
    }

    private var portalHost: String? {
        portalURL?.host
    }

    private func refreshCertificateStatus() {
        guard let portalHost,
              Preferences.trustedPortalCertificateFingerprint(for: portalHost) != nil else {
            savedCertificateHost = nil
            return
        }
        savedCertificateHost = portalHost
    }
}
