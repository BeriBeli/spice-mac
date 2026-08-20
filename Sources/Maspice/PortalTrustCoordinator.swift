// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Observation
import Security

@MainActor
@Observable
final class PortalTrustCoordinator {
    private(set) var challengedHost: String?
    private var challengedFingerprint: String?
    private var sessionCertificates = [String: String]()
    private var continuations: [CheckedContinuation<Bool, Never>] = []

    func requestTrust(for host: String, fingerprint: String) async -> Bool {
        let normalizedHost = host.lowercased()
        if sessionCertificates[normalizedHost] == fingerprint
                || Preferences.trustedPortalCertificateFingerprint(for: normalizedHost) == fingerprint {
            return true
        }

        if !continuations.isEmpty {
            guard challengedHost?.caseInsensitiveCompare(host) == .orderedSame,
                  challengedFingerprint == fingerprint else { return false }
            return await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }
        challengedHost = host
        challengedFingerprint = fingerprint
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resolve(_ decision: PortalTrustDecision) {
        guard !continuations.isEmpty else { return }
        let allowed = decision != .cancel
        if allowed, let challengedHost, let challengedFingerprint {
            let normalizedHost = challengedHost.lowercased()
            sessionCertificates[normalizedHost] = challengedFingerprint
            if decision == .always {
                Preferences.trustPortalCertificate(
                    host: normalizedHost,
                    fingerprint: challengedFingerprint)
            }
        }
        let pendingContinuations = continuations
        continuations.removeAll()
        challengedHost = nil
        challengedFingerprint = nil
        for continuation in pendingContinuations {
            continuation.resume(returning: allowed)
        }
    }

    func cancelPendingChallenge() {
        resolve(.cancel)
    }

    func trustedCertificate(for host: String?) -> PortalTrustedCertificate? {
        guard let host else { return nil }
        let normalizedHost = host.lowercased()
        let fingerprint = sessionCertificates[normalizedHost]
            ?? Preferences.trustedPortalCertificateFingerprint(for: normalizedHost)
        guard let fingerprint else { return nil }
        return PortalTrustedCertificate(host: normalizedHost, fingerprint: fingerprint)
    }
}

enum PortalTrustDecision {
    case cancel
    case session
    case always
}

struct PortalTrustedCertificate: Sendable {
    let host: String
    let fingerprint: String
}

enum PortalCertificateFingerprint {
    static func sha256(of trust: SecTrust) -> String? {
        guard let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leafCertificate = certificates.first else { return nil }
        let certificateData = SecCertificateCopyData(leafCertificate) as Data
        return SHA256.hash(data: certificateData)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
