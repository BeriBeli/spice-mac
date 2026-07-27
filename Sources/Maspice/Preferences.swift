// SPDX-License-Identifier: MIT
import Foundation

enum Preferences {
    static let shareClipboardKey = "ShareClipboard"
    static let trashConnectionFileAfterUseKey = "TrashConnectionFileAfterUse"
    static let ravadaPortalURLKey = "RavadaPortalURL"
    static let trustedPortalCertificatesKey = "TrustedPortalCertificates"

    static var shareClipboard: Bool {
        get { (UserDefaults.standard.object(forKey: shareClipboardKey) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: shareClipboardKey) }
    }

    static var trashConnectionFileAfterUse: Bool {
        get { (UserDefaults.standard.object(forKey: trashConnectionFileAfterUseKey) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: trashConnectionFileAfterUseKey) }
    }

    static func trustedPortalCertificateFingerprint(for host: String) -> String? {
        trustedPortalCertificates[host.lowercased()]
    }

    static func trustPortalCertificate(host: String, fingerprint: String) {
        var certificates = trustedPortalCertificates
        certificates[host.lowercased()] = fingerprint
        UserDefaults.standard.set(certificates, forKey: trustedPortalCertificatesKey)
    }

    static func forgetPortalCertificateTrust(for host: String) {
        var certificates = trustedPortalCertificates
        certificates.removeValue(forKey: host.lowercased())
        UserDefaults.standard.set(certificates, forKey: trustedPortalCertificatesKey)
    }

    private static var trustedPortalCertificates: [String: String] {
        UserDefaults.standard.dictionary(forKey: trustedPortalCertificatesKey) as? [String: String] ?? [:]
    }
}
