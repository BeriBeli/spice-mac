import Foundation
import Testing
import WebKit
@testable import Maspice

struct PortalCookieExpirationTests {
    private let portal = URL(string: "https://portal.example/")!
    private let serverDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func cookie(
        value: String = "test-session",
        host: String = "portal.example",
        expiry: Date?,
        maxAge: String? = nil
    ) -> HTTPCookie {
        let payload: [String: Any] = ["login": value, "expires": (expiry ?? serverDate).timeIntervalSince1970]
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let encoded = data.base64EncodedString().replacingOccurrences(of: "=", with: "-")
        let signedValue = encoded + "--" + String(repeating: "a", count: 64)
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: "mojolicious", .value: signedValue, .domain: host, .path: "/",
            .secure: "TRUE", .sameSitePolicy: "Lax",
            HTTPCookiePropertyKey("HttpOnly"): "TRUE",
        ]
        properties[.expires] = expiry
        properties[.maximumAge] = maxAge
        return HTTPCookie(properties: properties)!
    }

    private func response(url: URL? = nil, age: String? = nil) -> HTTPURLResponse {
        var headers = ["Date": "Tue, 14 Nov 2023 22:13:20 GMT"]
        headers["Age"] = age
        return HTTPURLResponse(url: url ?? portal, statusCode: 200,
                               httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    @Test func fiveMinuteClockSkewPreservesServerLifetimeAndCookieRestrictions() throws {
        let now = serverDate.addingTimeInterval(299)
        var policy = PortalCookieExpirationPolicy(portalURL: portal)
        policy.observe(response(), receivedAt: now)
        let original = cookie(expiry: serverDate.addingTimeInterval(300))
        let corrected = try #require(policy.corrections(for: [original], now: now).first)
        #expect(corrected.expiresDate == now.addingTimeInterval(300))
        #expect(corrected.value == original.value)
        #expect(corrected.domain == original.domain)
        #expect(corrected.path == original.path)
        #expect(corrected.isSecure == original.isSecure)
        #expect(corrected.isHTTPOnly == original.isHTTPOnly)
        #expect(corrected.sameSitePolicy == original.sameSitePolicy)
        #expect(policy.corrections(for: [corrected], now: now.addingTimeInterval(10)).isEmpty)
    }

    @Test func doesNotExtendCookiesAgainWhenPortalReopens() {
        let now = serverDate.addingTimeInterval(299)
        let original = cookie(expiry: serverDate.addingTimeInterval(300))
        var properties = original.properties!
        properties[.expires] = now.addingTimeInterval(300)
        let existing = HTTPCookie(properties: properties)!
        var policy = PortalCookieExpirationPolicy(portalURL: portal)
        policy.observe(response(), receivedAt: now)
        #expect(policy.corrections(for: [existing], now: now).isEmpty)
    }

    @Test func renewedCookieIsCorrectedOnceAndLogoutIsNotUndone() throws {
        let now = serverDate.addingTimeInterval(299)
        var policy = PortalCookieExpirationPolicy(portalURL: portal)
        policy.observe(response(), receivedAt: now)
        let first = cookie(expiry: serverDate.addingTimeInterval(300))
        let adjusted = try #require(policy.corrections(for: [first], now: now).first)
        #expect(policy.corrections(for: [adjusted], now: now).isEmpty)
        let renewal = cookie(value: "renewed-session", expiry: serverDate.addingTimeInterval(360))
        #expect(policy.corrections(for: [renewal], now: now).count == 1)
        #expect(policy.corrections(for: [], now: now).isEmpty)
        let deletion = cookie(value: "", expiry: serverDate.addingTimeInterval(-1))
        #expect(policy.corrections(for: [deletion], now: now).isEmpty)
    }

    @Test func sessionMaxAgeAndOtherHostCookiesAreUntouched() {
        let now = serverDate.addingTimeInterval(299)
        var policy = PortalCookieExpirationPolicy(portalURL: portal)
        policy.observe(response(), receivedAt: now)
        let cookies = [
            cookie(expiry: nil),
            cookie(value: "relative", expiry: serverDate.addingTimeInterval(300), maxAge: "300"),
            cookie(host: "other.example", expiry: serverDate.addingTimeInterval(300)),
        ]
        #expect(policy.corrections(for: cookies, now: now).isEmpty)
    }

    @Test(arguments: ["http://portal.example/", "https://other.example/", "https://portal.example:8443/"])
    func onlySameOriginHTTPSCanSetTheClock(_ url: String) {
        var policy = PortalCookieExpirationPolicy(portalURL: portal)
        policy.observe(response(url: URL(string: url)!), receivedAt: serverDate.addingTimeInterval(299))
        #expect(policy.clockOffset == nil)
    }

    @Test func cacheAgeAndNormalClockRoundingDoNotExtendCookies() {
        var policy = PortalCookieExpirationPolicy(portalURL: portal)
        let now = serverDate.addingTimeInterval(300)
        policy.observe(response(age: "299"), receivedAt: now)
        #expect(policy.clockOffset == 1)
        #expect(policy.corrections(for: [cookie(expiry: now.addingTimeInterval(300))], now: now).isEmpty)
    }

    @Test func serverClockAheadShortensLocalExpiryByTheSameOffset() throws {
        var policy = PortalCookieExpirationPolicy(portalURL: portal)
        let now = serverDate.addingTimeInterval(-299)
        policy.observe(response(), receivedAt: now)
        let corrected = try #require(policy.corrections(
            for: [cookie(expiry: serverDate.addingTimeInterval(300))], now: now).first)
        #expect(corrected.expiresDate == now.addingTimeInterval(300))
    }

    @Test func legacyMojoliciousPaddingIsSupportedWithoutChangingTheSignedValue() throws {
        let now = serverDate.addingTimeInterval(299)
        var policy = PortalCookieExpirationPolicy(portalURL: portal)
        policy.observe(response(), receivedAt: now)
        var properties = cookie(expiry: serverDate.addingTimeInterval(300)).properties!
        let json = "{\"expires\":1700000300,\"login\":\"test\"}ZZ"
        let value = Data(json.utf8).base64EncodedString() + "--" + String(repeating: "b", count: 64)
        properties[.value] = value
        let original = try #require(HTTPCookie(properties: properties))
        let corrected = try #require(policy.corrections(for: [original], now: now).first)
        #expect(corrected.value == value)
        #expect(corrected.expiresDate == now.addingTimeInterval(300))
    }

    @Test(arguments: ["opaque-session", "invalid--signature", "!!!!--" + String(repeating: "a", count: 64)])
    func unrecognizedSessionFormatsRemainUntouched(_ value: String) throws {
        let now = serverDate.addingTimeInterval(299)
        var policy = PortalCookieExpirationPolicy(portalURL: portal)
        policy.observe(response(), receivedAt: now)
        var properties = cookie(expiry: serverDate.addingTimeInterval(300)).properties!
        properties[.value] = value
        let original = try #require(HTTPCookie(properties: properties))
        #expect(policy.corrections(for: [original], now: now).isEmpty)
    }

    private func loginResponse(expiry: Date, status: Int = 302, extra: String = "") -> HTTPURLResponse {
        let signed = cookie(expiry: expiry)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return HTTPURLResponse(url: portal, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [
            "Date": "Tue, 14 Nov 2023 22:13:20 GMT",
            "Set-Cookie": "mojolicious=\(signed.value); Expires=\(formatter.string(from: expiry)); Path=/; Secure; HttpOnly; SameSite=Lax\(extra)",
            "Location": "/machines",
        ])!
    }

    @Test(arguments: [300.0, 301.0, 3600.0])
    func loginRedirectRecoversCookieAlreadyExpiredOnTheMac(_ offset: TimeInterval) throws {
        let now = serverDate.addingTimeInterval(offset)
        var policy = PortalCookieExpirationPolicy(portalURL: portal)
        // No stored cookie exists: the 0.5.4 observer has nothing to correct.
        #expect(policy.corrections(for: [], now: now).isEmpty)
        let response = loginResponse(expiry: serverDate.addingTimeInterval(300))
        let corrected = try #require(policy.cookies(from: response, receivedAt: now).first)
        #expect(corrected.expiresDate == now.addingTimeInterval(300))
        #expect(corrected.isSecure && corrected.isHTTPOnly)
        #expect(corrected.sameSitePolicy?.rawValue.lowercased() == "lax")
        #expect(corrected.value == cookie(expiry: serverDate.addingTimeInterval(300)).value)
        #expect(policy.corrections(for: [corrected], now: now).isEmpty)
    }

    @Test func renewalResponseIsRecoveredEvenWhenCookieStoreIsEmpty() throws {
        var policy = PortalCookieExpirationPolicy(portalURL: portal)
        let now = serverDate.addingTimeInterval(305)
        let response = loginResponse(expiry: serverDate.addingTimeInterval(300), status: 200)
        let corrected = try #require(policy.correctedCookies(from: response, receivedAt: now).first)
        #expect(corrected.expiresDate == now.addingTimeInterval(300))
    }

    @Test func cachedOldResponseCannotMoveClockOrReviveExpiredSession() {
        var policy = PortalCookieExpirationPolicy(portalURL: portal)
        let initialNow = serverDate.addingTimeInterval(300)
        policy.observe(response(), receivedAt: initialNow)
        let oldResponse = loginResponse(expiry: serverDate.addingTimeInterval(300), status: 200)
        #expect(policy.correctedCookies(from: oldResponse, receivedAt: initialNow.addingTimeInterval(600)).isEmpty)
        #expect(policy.clockOffset == 300)
    }

    @Test func rawLogoutAndMaxAgeAreNeverRevivedOrExtended() throws {
        var policy = PortalCookieExpirationPolicy(portalURL: portal)
        let now = serverDate.addingTimeInterval(305)
        let logout = loginResponse(expiry: serverDate.addingTimeInterval(-1))
        #expect(policy.correctedCookies(from: logout, receivedAt: now).isEmpty)
        let deletion = try #require(policy.cookies(from: logout, receivedAt: now).first)
        #expect(try #require(deletion.expiresDate) < now)
        let relative = loginResponse(expiry: serverDate.addingTimeInterval(300), extra: "; Max-Age=300")
        #expect(policy.correctedCookies(from: relative, receivedAt: now).isEmpty)
    }

    @Test func responseFromAnotherOriginCannotImportCookies() {
        var policy = PortalCookieExpirationPolicy(portalURL: portal)
        let response = HTTPURLResponse(url: URL(string: "https://portal.example:8443/")!, statusCode: 302,
            httpVersion: "HTTP/1.1", headerFields: ["Set-Cookie": "mojolicious=unrelated; Path=/"])!
        #expect(policy.cookies(from: response, receivedAt: serverDate).isEmpty)
        let foreignDomain = loginResponse(expiry: serverDate.addingTimeInterval(300), extra: "; Domain=other.example")
        #expect(policy.cookies(from: foreignDomain, receivedAt: serverDate.addingTimeInterval(305)).isEmpty)
    }

    @Test @MainActor func webKitStoresRecoveredCookieAndHonorsLogout() async throws {
        let dataStore = WKWebsiteDataStore.nonPersistent()
        defer { withExtendedLifetime(dataStore) {} }
        let store = dataStore.httpCookieStore
        let now = Date()
        let remoteNow = now.addingTimeInterval(-600)
        let expiry = remoteNow.addingTimeInterval(300)
        let original = cookie(expiry: expiry)
        await store.setCookie(original)
        #expect(await store.allCookies().isEmpty)
        var policy = PortalCookieExpirationPolicy(portalURL: portal)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let response = HTTPURLResponse(url: portal, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: [
            "Date": formatter.string(from: remoteNow),
            "Set-Cookie": "mojolicious=\(original.value); Expires=\(formatter.string(from: expiry)); Path=/; HttpOnly; Secure; SameSite=Lax",
        ])!
        let corrected = try #require(policy.cookies(from: response, receivedAt: now).first)
        #expect(try #require(corrected.expiresDate) > now.addingTimeInterval(299))
        await store.setCookie(corrected)
        let stored = try #require(await store.allCookies().first)
        #expect(stored.value == original.value)
        #expect(try #require(stored.expiresDate) > now.addingTimeInterval(299))
        #expect(stored.isHTTPOnly && stored.isSecure)
        let logout = HTTPURLResponse(url: portal, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: [
            "Date": formatter.string(from: remoteNow),
            "Set-Cookie": "mojolicious=; Expires=Thu, 01 Jan 1970 00:00:01 GMT; Path=/; HttpOnly; Secure",
        ])!
        for deletion in policy.cookies(from: logout, receivedAt: now) { await store.setCookie(deletion) }
        #expect(await store.allCookies().isEmpty)
    }
}
