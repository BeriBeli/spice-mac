import Foundation
import Testing
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
        let data = try! JSONSerialization.data(withJSONObject: payload)
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
}
