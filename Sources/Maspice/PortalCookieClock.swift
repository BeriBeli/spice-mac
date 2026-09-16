// SPDX-License-Identifier: MIT
import Foundation
import WebKit

/// Correct only Ravada/Mojolicious session cookies whose stored expiry still
/// matches the absolute expiry in their signed payload. WebKit normalizes away
/// Max-Age, so the payload is needed to distinguish an uncorrected Expires date
/// from an already-adjusted or relative expiry. Cookie values are never changed.
struct PortalCookieExpirationPolicy {
    private let portalURL: URL
    private(set) var clockOffset: TimeInterval?

    init(portalURL: URL) {
        self.portalURL = portalURL
    }

    mutating func observe(_ response: HTTPURLResponse, receivedAt: Date) {
        guard clockOffset == nil,
              let url = response.url,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == portalURL.host?.lowercased(),
              (url.port ?? 443) == (portalURL.port ?? 443),
              let header = response.value(forHTTPHeaderField: "Date") else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let serverDate = formatter.date(from: header) else { return }
        let age = max(0, TimeInterval(response.value(forHTTPHeaderField: "Age") ?? "") ?? 0)
        clockOffset = receivedAt.timeIntervalSince(serverDate) - age
    }

    func corrections(for cookies: [HTTPCookie], now: Date) -> [HTTPCookie] {
        // Ignore ordinary HTTP timestamp rounding and transport latency.
        guard let clockOffset, abs(clockOffset) > 60 else { return [] }
        return cookies.compactMap { cookie in
            guard cookie.name == "mojolicious",
                  cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    .lowercased() == portalURL.host?.lowercased(),
                  let expiry = cookie.expiresDate,
                  let serverExpiry = Self.sessionExpiry(cookie.value),
                  abs(expiry.timeIntervalSince(serverExpiry)) < 1,
                  var properties = cookie.properties,
                  properties[.maximumAge] == nil,
                  // Preserve logout and server-side session expiration.
                  serverExpiry > now.addingTimeInterval(-clockOffset) else { return nil }
            properties[.expires] = serverExpiry.addingTimeInterval(clockOffset)
            return HTTPCookie(properties: properties)
        }
    }

    private static func sessionExpiry(_ value: String) -> Date? {
        guard value.utf8.count <= 16_384,
              let separator = value.range(of: "--", options: .backwards) else { return nil }
        let signature = value[separator.upperBound...]
        guard [40, 64].contains(signature.count),
              signature.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        // Mojolicious replaces base64 padding '=' with '-'. Older versions
        // instead append 'Z' bytes after the JSON object before encoding it.
        var encoded = String(value[..<separator.lowerBound]).replacingOccurrences(of: "-", with: "=")
        while encoded.count % 4 != 0 { encoded += "=" }
        guard var data = Data(base64Encoded: encoded) else { return nil }
        while data.last == 0x5a { data.removeLast() }
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expires = payload["expires"] as? Double, expires.isFinite else { return nil }
        // This reads expiry metadata, not authentication authority. The server
        // still validates the unchanged signature and session on every request.
        return Date(timeIntervalSince1970: expires)
    }
}

@MainActor
final class PortalCookieClock: NSObject, WKHTTPCookieStoreObserver {
    private let store: WKHTTPCookieStore
    private var policy: PortalCookieExpirationPolicy
    private var isObserving = false
    private var needsSynchronization = false
    private var synchronization: Task<Void, Never>?
    private var generation = 0

    init(store: WKHTTPCookieStore, portalURL: URL) {
        self.store = store
        policy = PortalCookieExpirationPolicy(portalURL: portalURL)
    }

    func start() {
        guard !isObserving else { return }
        store.add(self)
        isObserving = true
    }

    isolated deinit {
        store.remove(self)
        synchronization?.cancel()
    }

    func observe(_ response: URLResponse) {
        guard isObserving, let response = response as? HTTPURLResponse else { return }
        policy.observe(response, receivedAt: Date())
        scheduleSynchronization()
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        scheduleSynchronization()
    }

    func stop() {
        isObserving = false
        generation += 1
        store.remove(self)
        synchronization?.cancel()
        synchronization = nil
    }

    private func scheduleSynchronization() {
        guard isObserving else { return }
        needsSynchronization = true
        guard synchronization == nil else { return }
        let generation = self.generation
        synchronization = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == generation { self.synchronization = nil }
            }
            while self.needsSynchronization && !Task.isCancelled {
                self.needsSynchronization = false
                let cookies = await self.store.allCookies()
                guard !Task.isCancelled, self.isObserving,
                      self.generation == generation else { return }
                let corrected = self.policy.corrections(for: cookies, now: Date())
                if !corrected.isEmpty {
                    await self.store.setCookies(corrected)
                }
            }
        }
    }
}
