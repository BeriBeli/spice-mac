import Foundation
import Testing
import WebKit
import os
@testable import Maspice

@MainActor
struct PortalLoginTests {
    private let portal = URL(string: "https://portal.example/")!

    @Test(arguments: [301, 302, 303])
    func loginRedirectCanOnlyBecomeASameOriginGET(_ status: Int) throws {
        let response = HTTPURLResponse(url: portal, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Location": "/machines?view=mine"])!
        #expect(try PortalLoginCoordinator.redirect(from: response, portalURL: portal)
            == URL(string: "https://portal.example/machines?view=mine"))
    }

    @Test(arguments: ["http://portal.example/", "https://other.example/", "//other.example/",
                      "https://portal.example:8443/", "https://user:pass@portal.example/"])
    func unsafeRedirectNeverReceivesCredentials(_ location: String) {
        let response = HTTPURLResponse(url: portal, statusCode: 302, httpVersion: "HTTP/1.1",
                                       headerFields: ["Location": location])!
        #expect(throws: (any Error).self) {
            try PortalLoginCoordinator.redirect(from: response, portalURL: portal)
        }
    }

    @Test(arguments: [307, 308])
    func passwordPOSTIsNeverReplayed(_ status: Int) {
        let response = HTTPURLResponse(url: portal, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Location": "/retry"])!
        #expect(throws: (any Error).self) {
            try PortalLoginCoordinator.redirect(from: response, portalURL: portal)
        }
    }

    @Test func failedLoginRemainsAResponseInsteadOfARedirect() throws {
        let response = HTTPURLResponse(url: portal, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: [:])!
        #expect(try PortalLoginCoordinator.redirect(from: response, portalURL: portal) == nil)
    }

    @Test func originHeaderOmitsCredentialsPathQueryAndFragment() {
        #expect(PortalLoginCoordinator.origin(of: URL(string: "https://portal.example:8443/login?token=private#fragment")!)
            == "https://portal.example:8443")
    }

    @Test func isolatedFormCapturePreservesEncodingAndSubmitterWithoutResubmitting() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(PortalLoginCoordinator.captureScript)
        let view = WKWebView(frame: .zero, configuration: configuration)
        let loader = FormPageLoader()
        view.navigationDelegate = loader
        view.loadSimulatedRequest(URLRequest(url: portal), responseHTML: """
        <form method="post" action="/login"><input name="username" value="a+b &amp; 中文">
        <input type="password" name="password" value="synthetic-only&amp;=+">
        <input type="hidden" name="csrf" value="test-token">
        <input disabled name="ignored" value="ignore">
        <button name="login" value="1">Login</button></form>
        """)
        for _ in 0..<100 {
            if loader.loaded { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(loader.loaded)
        let body = try await view.callAsyncJavaScript("""
            const form = document.querySelector('form');
            form.dispatchEvent(new SubmitEvent('submit', {bubbles:true, submitter:form.querySelector('button')}));
            return globalThis.maspiceTakeLoginForm('https://portal.example/login');
            """, in: nil, contentWorld: .defaultClient) as? String
        #expect(body == "username=a%2Bb+%26+%E4%B8%AD%E6%96%87&password=synthetic-only%26%3D%2B&csrf=test-token&login=1")
        let second = try await view.callAsyncJavaScript(
            "return globalThis.maspiceTakeLoginForm('https://portal.example/login');", in: nil, contentWorld: .defaultClient)
        #expect(second == nil || second is NSNull)
        let foreign = try await view.callAsyncJavaScript("""
            const form = document.querySelector('form');
            form.action = 'https://other.example/login';
            form.dispatchEvent(new SubmitEvent('submit', {bubbles:true}));
            return globalThis.maspiceTakeLoginForm('https://other.example/login');
            """, in: nil, contentWorld: .defaultClient)
        #expect(foreign == nil || foreign is NSNull)
        let pageWorld = try await view.callAsyncJavaScript(
            "return typeof globalThis.maspiceTakeLoginForm;", in: nil, contentWorld: .page) as? String
        #expect(pageWorld == "undefined")
    }

    @Test func nativeLoginStoresTheRedirectCookieBeforeTheNextNavigation() async throws {
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let clock = PortalCookieClock(store: dataStore.httpCookieStore, portalURL: portal)
        clock.start()
        defer { clock.stop() }
        let serverNow = Date().addingTimeInterval(-600)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        await clock.observe(HTTPURLResponse(url: portal, statusCode: 401, httpVersion: "HTTP/1.1",
                                           headerFields: ["Date": formatter.string(from: serverNow)])!)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [LoginFixtureProtocol.self]
        let decider = LoginFixtureDecider(store: dataStore.httpCookieStore)
        let login = PortalLoginCoordinator(portalURL: portal, store: dataStore.httpCookieStore,
            clock: clock, trust: PortalTrustCoordinator(), configuration: sessionConfiguration,
            onError: { decider.error = $0 })
        decider.login = login
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = dataStore
        configuration.userContentController.addUserScript(PortalLoginCoordinator.captureScript)
        let page = WebPage(configuration: configuration, navigationDecider: decider)
        login.page = page
        LoginFixtureProtocol.requests.withLock { $0.removeAll() }
        page.load(simulatedRequest: URLRequest(url: portal), responseHTML: """
        <form method="post"><input name="username" value="test-user">
        <input type="password" name="password" value="synthetic-password">
        <input type="hidden" name="csrf" value="fixture-token"><button>Login</button></form>
        """)
        for _ in 0..<100 {
            if page.url != nil && !page.isLoading { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(page.url == portal)
        _ = try await page.callJavaScript("document.querySelector('form').requestSubmit();")
        for _ in 0..<100 {
            if decider.reachedDestination || decider.error != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(decider.error == nil)
        #expect(decider.reachedDestination)
        #expect(decider.hadCorrectedCookie)
        let requests = LoginFixtureProtocol.requests.withLock { $0 }
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Origin") == "https://portal.example")
        #expect(request.url == portal)
        login.cancel()
    }
}

@MainActor private final class FormPageLoader: NSObject, WKNavigationDelegate {
    var loaded = false
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true }
}

@MainActor private final class LoginFixtureDecider: WebPage.NavigationDeciding {
    let store: WKHTTPCookieStore
    var login: PortalLoginCoordinator?
    var reachedDestination = false
    var hadCorrectedCookie = false
    var error: String?
    init(store: WKHTTPCookieStore) { self.store = store }
    func decidePolicy(for action: WebPage.NavigationAction,
                      preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
        if action.request.url?.path == "/machines" {
            reachedDestination = action.request.httpMethod == "GET"
            let cookies = await store.allCookies()
            hadCorrectedCookie = cookies.contains {
                $0.name == "mojolicious" && ($0.expiresDate?.timeIntervalSinceNow ?? 0) > 290
            }
            return .cancel
        }
        if await login?.intercept(action) == true { return .cancel }
        return .allow
    }
}

private final class LoginFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let requests = OSAllocatedUnfairLock(initialState: [URLRequest]())
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "portal.example" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.withLock { $0.append(request) }
        let serverNow = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 600)
        let expiry = serverNow.addingTimeInterval(300)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let payload = try! JSONSerialization.data(withJSONObject: ["expires": expiry.timeIntervalSince1970])
        let value = payload.base64EncodedString().replacingOccurrences(of: "=", with: "-")
            + "--" + String(repeating: "a", count: 64)
        let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: [
            "Date": formatter.string(from: serverNow), "Location": "/machines",
            "Set-Cookie": "mojolicious=\(value); Expires=\(formatter.string(from: expiry)); Path=/; HttpOnly; Secure; SameSite=Lax",
        ])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("redirect".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
