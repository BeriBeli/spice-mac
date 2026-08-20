// SPDX-License-Identifier: MIT
import SwiftUI

struct PortalSettingsView: View {
    @AppStorage(Preferences.ravadaPortalURLKey) private var ravadaPortalURL = ""
    @State private var savedCertificateHost: String?
    @State private var forgottenCertificateHost: String?

    var body: some View {
        Form {
            Section("Ravada Portal") {
                TextField(
                    "Portal URL",
                    text: $ravadaPortalURL,
                    prompt: Text("https://vdi.example.com/"))
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
                CertificateSettingsView(
                    portalHost: portalHost,
                    savedCertificateHost: savedCertificateHost,
                    forgottenCertificateHost: forgottenCertificateHost,
                    onForget: forgetCertificate)
            }
        }
        .formStyle(.grouped)
        .scenePadding()
        .task {
            refreshCertificateStatus()
        }
        .onChange(of: ravadaPortalURL) {
            forgottenCertificateHost = nil
            refreshCertificateStatus()
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

    private func forgetCertificate(for portalHost: String) {
        Preferences.forgetPortalCertificateTrust(for: portalHost)
        savedCertificateHost = nil
        forgottenCertificateHost = portalHost
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

private struct CertificateSettingsView: View {
    let portalHost: String?
    let savedCertificateHost: String?
    let forgottenCertificateHost: String?
    let onForget: (String) -> Void

    var body: some View {
        if let portalHost, savedCertificateHost == portalHost {
            LabeledContent("Saved for") {
                Text(portalHost)
                    .foregroundStyle(.secondary)
            }

            Button("Forget Saved Certificate") {
                onForget(portalHost)
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
}
