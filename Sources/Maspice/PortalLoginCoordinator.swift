// SPDX-License-Identifier: MIT
import Foundation
import Observation
import Security
import WebKit

/// Only the same-origin, top-level password form needs a native round trip when
/// the portal clock is skewed. WebKit omits POST bodies from navigation actions;
/// capture the submitted form in an isolated world without changing submission.
/// Credentials live only in memory for this request; never log or persist them.
@MainActor
@Observable
final class PortalLoginCoordinator {
    static let captureSource = #"""
    (() => {
        let submission = null;
        document.addEventListener('submit', event => {
            const form = event.target;
            submission = form instanceof HTMLFormElement
                ? {form, submitter: event.submitter} : null;
        }, true);
        globalThis.maspiceTakeLoginForm = expectedURL => {
            const pending = submission;
            submission = null;
            if (!pending) return null;
            const {form, submitter} = pending;
            const action = new URL(submitter?.hasAttribute('formaction')
                ? submitter.formAction : form.action, document.baseURI);
            const expected = new URL(expectedURL);
            action.hash = expected.hash = '';
            const method = submitter?.getAttribute('formmethod') || form.method;
            const encoding = submitter?.getAttribute('formenctype') || form.enctype;
            if (action.href !== expected.href || action.origin !== location.origin
                || method.toLowerCase() !== 'post'
                || encoding !== 'application/x-www-form-urlencoded'
                || !form.querySelector('input[type="password"]')) return null;
            const data = new FormData(form, submitter);
            const body = new URLSearchParams();
            for (const [key, value] of data) {
                if (typeof value !== 'string') return null;
                body.append(key.replace(/\r?\n|\r/g, '\r\n'),
                            value.replace(/\r?\n|\r/g, '\r\n'));
            }
            return body.toString();
        };
    })();
    """#

    static var captureScript: WKUserScript {
        WKUserScript(source: captureSource, injectionTime: .atDocumentStart,
                     forMainFrameOnly: true, in: .defaultClient)
    }

    weak var page: WebPage?
    private let portalURL: URL
    private let store: WKHTTPCookieStore
    private let clock: PortalCookieClock
    private let trust: PortalTrustCoordinator
    private let onError: @MainActor (String) -> Void
    private let configuration: URLSessionConfiguration
    private(set) var isSubmitting = false
    private var task: Task<Void, Never>?
    private var generation = 0

    init(portalURL: URL, store: WKHTTPCookieStore, clock: PortalCookieClock,
         trust: PortalTrustCoordinator, configuration: URLSessionConfiguration = .ephemeral,
         onError: @escaping @MainActor (String) -> Void) {
        self.portalURL = portalURL
        self.store = store
        self.clock = clock
        self.trust = trust
        self.onError = onError
        self.configuration = configuration
    }

    func intercept(_ action: WebPage.NavigationAction) async -> Bool {
        guard clock.needsClockCorrection,
              action.navigationType == .formSubmitted,
              action.source.isMainFrame, action.target?.isMainFrame == true,
              action.source.securityOrigin.protocol == "https",
              action.source.securityOrigin.host.lowercased() == portalURL.host?.lowercased(),
              Self.normalizedPort(action.source.securityOrigin.port) == (portalURL.port ?? 443),
              let url = action.request.url, isPortalOrigin(url),
              action.request.httpMethod == "POST", let page else { return false }
        guard task == nil else { return true }
        let currentGeneration = generation
        do {
            guard let body = try await page.callJavaScript(
                "return globalThis.maspiceTakeLoginForm?.(url) ?? null;",
                arguments: ["url": url.absoluteString], contentWorld: .defaultClient) as? String else {
                return false
            }
            guard generation == currentGeneration, !Task.isCancelled else { return true }
            guard body.utf8.count <= 256 * 1024 else {
                onError("The portal login form is too large to submit.")
                return true
            }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.httpMethod = "POST"
            request.httpBody = Data(body.utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue(Self.origin(of: url), forHTTPHeaderField: "Origin")
            // Preserve WebKit's referrer policy; never synthesize a full page URL.
            for header in ["Referer", "User-Agent", "Accept", "Accept-Language"] {
                request.setValue(action.request.value(forHTTPHeaderField: header), forHTTPHeaderField: header)
            }
            isSubmitting = true
            task = Task { [weak self] in
                await self?.submit(request, generation: currentGeneration)
            }
            return true
        } catch {
            onError("Could not read the portal login form. Reload the portal and try again.")
            return true
        }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        isSubmitting = false
    }

    private func isPortalOrigin(_ url: URL) -> Bool {
        PortalCookieExpirationPolicy(portalURL: portalURL).isPortalOrigin(url)
    }

    private static func normalizedPort(_ port: Int) -> Int { port == 0 ? 443 : port }

    static func origin(of url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.user = nil; components.password = nil
        components.path = ""; components.query = nil; components.fragment = nil
        return components.string!
    }

    /// Never replay credentials on redirects, including a 307/308 or another
    /// port on the same host. Only a same-origin GET may follow a login POST.
    static func redirect(from response: HTTPURLResponse, portalURL: URL) throws -> URL? {
        guard (300..<400).contains(response.statusCode) else { return nil }
        guard [301, 302, 303].contains(response.statusCode),
              let location = response.value(forHTTPHeaderField: "Location"),
              let url = URL(string: location, relativeTo: response.url)?.absoluteURL,
              url.user == nil, url.password == nil,
              PortalCookieExpirationPolicy(portalURL: portalURL).isPortalOrigin(url) else {
            throw LoginError.invalidRedirect
        }
        return url
    }

    private func submit(_ originalRequest: URLRequest, generation: Int) async {
        defer { if self.generation == generation { task = nil; isSubmitting = false } }
        let delegate = PortalLoginSessionDelegate(
            portalURL: portalURL, certificate: trust.trustedCertificate(for: portalURL.host))
        let configuration = configuration.copy() as! URLSessionConfiguration
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            var request = originalRequest
            request.httpShouldHandleCookies = false
            let cookies = await store.allCookies().filter {
                RavadaNavigationDecider.cookie($0, appliesTo: originalRequest.url!)
            }
            for (key, value) in HTTPCookie.requestHeaderFields(with: cookies) {
                request.setValue(value, forHTTPHeaderField: key)
            }
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse,
                  let responseURL = response.url, isPortalOrigin(responseURL) else {
                throw LoginError.invalidResponse
            }
            let redirect = try Self.redirect(from: response, portalURL: portalURL)
            guard response.expectedContentLength <= 2 * 1024 * 1024 else {
                throw LoginError.invalidResponse
            }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 2 * 1024 * 1024 else { throw LoginError.invalidResponse }
                data.append(byte)
            }
            try Task.checkCancellation()
            guard self.generation == generation, let page else { return }
            await clock.storeCookies(from: response)
            try Task.checkCancellation()
            guard self.generation == generation else { return }
            if let redirect {
                page.load(URLRequest(url: redirect, cachePolicy: .reloadIgnoringLocalCacheData))
            } else {
                // Render failed-login HTML without resubmitting the password or
                // letting an unadjusted Set-Cookie overwrite the corrected one.
                guard response.mimeType == "text/html" else { throw LoginError.invalidResponse }
                let headers = response.allHeaderFields.reduce(into: [String: String]()) {
                    if let key = $1.key as? String, key.lowercased() != "set-cookie",
                       key.lowercased() != "content-encoding", key.lowercased() != "content-length",
                       let value = $1.value as? String { $0[key] = value }
                }
                let displayResponse = HTTPURLResponse(url: responseURL, statusCode: response.statusCode,
                                                     httpVersion: "HTTP/1.1", headerFields: headers)!
                page.load(simulatedRequest: URLRequest(url: responseURL),
                          response: displayResponse, responseData: data)
            }
        } catch {
            guard !Task.isCancelled, self.generation == generation else { return }
            onError("Could not complete the portal login. Reload the portal and try again.")
        }
    }

    private enum LoginError: Error { case invalidRedirect, invalidResponse }
}

/// Redirects are deliberately returned to the coordinator before URLSession
/// can follow them or discard their locally expired authentication cookies.
private final class PortalLoginSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let portalURL: URL
    private let certificate: PortalTrustedCertificate?

    init(portalURL: URL, certificate: PortalTrustedCertificate?) {
        self.portalURL = portalURL
        self.certificate = certificate
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              space.host.lowercased() == portalURL.host?.lowercased(),
              space.port == (portalURL.port ?? 443),
              let certificate, let trust = space.serverTrust,
              PortalCertificateFingerprint.sha256(of: trust) == certificate.fingerprint else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
