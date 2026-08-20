// SPDX-License-Identifier: MIT
import Foundation
import Security
import VVConfig
import WebKit

@MainActor
final class RavadaNavigationDecider: WebPage.NavigationDeciding {
    private let dataStore: WKWebsiteDataStore
    private let portalHost: String
    private let trustCoordinator: PortalTrustCoordinator
    private let onConnectionFile: @MainActor (URL) -> Void
    private let onError: @MainActor (String) -> Void
    private var downloadInFlight = false
    private var connectionWasDelivered = false
    private var downloadTask: Task<Void, Never>?

    init(
        dataStore: WKWebsiteDataStore,
        portalURL: URL,
        trustCoordinator: PortalTrustCoordinator,
        onConnectionFile: @escaping @MainActor (URL) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        self.dataStore = dataStore
        portalHost = portalURL.host?.lowercased() ?? ""
        self.trustCoordinator = trustCoordinator
        self.onConnectionFile = onConnectionFile
        self.onError = onError
    }

    func decidePolicy(
        for action: WebPage.NavigationAction,
        preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        guard Self.isConnectionFile(action.request.url) else { return .allow }
        guard isAllowedConnectionURL(action.request.url) else {
            onError("The portal tried to open a connection file from an untrusted address. No connection was made.")
            return .cancel
        }
        guard isUserInitiated(action) else {
            onError("The portal tried to open a connection file without a verified user action. No connection was made.")
            return .cancel
        }
        guard !connectionWasDelivered else { return .cancel }
        guard !downloadInFlight else { return .cancel }
        downloadInFlight = true
        let request = action.request
        downloadTask = Task { await downloadConnectionFile(request) }
        return .cancel
    }

    func decideAuthenticationChallengeDisposition(
        for challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let protectionSpace = challenge.protectionSpace
        guard protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              protectionSpace.host.caseInsensitiveCompare(portalHost) == .orderedSame,
              let serverTrust = protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }

        if SecTrustEvaluateWithError(serverTrust, nil) {
            return (.performDefaultHandling, nil)
        }

        guard let fingerprint = PortalCertificateFingerprint.sha256(of: serverTrust) else {
            return (.performDefaultHandling, nil)
        }
        let allowed = await trustCoordinator.requestTrust(
            for: protectionSpace.host,
            fingerprint: fingerprint)
        guard allowed else {
            onError("The portal certificate was not trusted. No connection was made.")
            return (.cancelAuthenticationChallenge, nil)
        }
        return (.useCredential, URLCredential(trust: serverTrust))
    }

    func decidePolicy(
        for response: WebPage.NavigationResponse
    ) async -> WKNavigationResponsePolicy {
        guard Self.isConnectionFile(response.response.url)
                || Self.isConnectionFileName(response.response.suggestedFilename) else {
            return .allow
        }
        // Direct .vv requests are intercepted in the action policy. Replaying a
        // response here would lose POST bodies and action-specific headers.
        if !downloadInFlight && !connectionWasDelivered {
            onError("The portal returned a connection file from an unsupported download URL.")
        }
        return .cancel
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadInFlight = false
    }

    private func downloadConnectionFile(_ originalRequest: URLRequest) async {
        defer {
            downloadInFlight = false
            downloadTask = nil
        }
        do {
            var request = originalRequest
            guard let requestURL = request.url,
                  isAllowedConnectionURL(requestURL) else {
                throw PortalDownloadError.invalidResponse
            }

            request.httpShouldHandleCookies = false
            let cookies = await allCookies().filter { Self.cookie($0, appliesTo: requestURL) }
            let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
            for (field, value) in cookieHeaders {
                request.setValue(value, forHTTPHeaderField: field)
            }

            let sessionDelegate = PortalURLSessionDelegate(
                expectedHost: portalHost,
                trustedCertificate: trustCoordinator.trustedCertificate(for: requestURL.host))
            let session = URLSession(
                configuration: .ephemeral,
                delegate: sessionDelegate,
                delegateQueue: nil)
            defer { session.finishTasksAndInvalidate() }
            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  httpResponse.expectedContentLength <= Int64(VVConfig.maxFileBytes)
                    || httpResponse.expectedContentLength == NSURLSessionTransferSizeUnknown else {
                throw PortalDownloadError.invalidResponse
            }

            var data = Data()
            data.reserveCapacity(min(
                max(Int(httpResponse.expectedContentLength), 0),
                VVConfig.maxFileBytes))
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < VVConfig.maxFileBytes else {
                    throw PortalDownloadError.responseTooLarge
                }
                data.append(byte)
            }
            guard !data.isEmpty,
                  let contents = String(data: data, encoding: .utf8) else {
                throw PortalDownloadError.invalidResponse
            }
            _ = try VVConfig.parse(contents)

            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("Maspice-\(UUID().uuidString).vv")
            try data.write(to: destination, options: .atomic)
            do {
                try Task.checkCancellation()
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
            connectionWasDelivered = true
            onConnectionFile(destination)
        } catch is CancellationError {
            return
        } catch {
            guard !connectionWasDelivered else { return }
            onError("Could not download the connection file.\n\(error.localizedDescription)")
        }
    }

    private func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            dataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private static func isConnectionFile(_ url: URL?) -> Bool {
        url?.pathExtension.lowercased() == "vv"
    }

    private static func isConnectionFileName(_ name: String?) -> Bool {
        guard let name else { return false }
        return URL(fileURLWithPath: name).pathExtension.lowercased() == "vv"
    }

    private func isAllowedConnectionURL(_ url: URL?) -> Bool {
        guard let url,
              url.scheme?.lowercased() == "https",
              url.host?.caseInsensitiveCompare(portalHost) == .orderedSame else { return false }
        return true
    }

    private func isUserInitiated(_ action: WebPage.NavigationAction) -> Bool {
        guard action.source.isMainFrame,
              action.source.securityOrigin.host.caseInsensitiveCompare(portalHost) == .orderedSame else {
            return false
        }
        switch action.navigationType {
        case .linkActivated, .formSubmitted, .formResubmitted:
            return true
        case .other:
            // Ravada's generated .vv download link is reported as `.other` by
            // native WebPage. A primary-button event still proves a real click.
            return action.buttonNumber == 0
        case .backForward, .reload:
            return false
        @unknown default:
            return false
        }
    }

    private static func cookie(_ cookie: HTTPCookie, appliesTo url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let isDomainCookie = cookie.domain.hasPrefix(".")
        let cookieDomain = cookie.domain
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        let domainMatches = host == cookieDomain
            || (isDomainCookie && host.hasSuffix(".\(cookieDomain)"))
        let requestPath = url.path.isEmpty ? "/" : url.path
        let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
        let pathMatches = requestPath == cookiePath
            || (requestPath.hasPrefix(cookiePath)
                && (cookiePath.hasSuffix("/")
                    || requestPath.dropFirst(cookiePath.count).first == "/"))
        let securityMatches = !cookie.isSecure || url.scheme?.lowercased() == "https"
        let hasNotExpired = cookie.expiresDate.map { $0 > Date() } ?? true
        return domainMatches && pathMatches && securityMatches && hasNotExpired
    }
}

private final class PortalURLSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let expectedHost: String
    private let trustedCertificate: PortalTrustedCertificate?

    init(expectedHost: String, trustedCertificate: PortalTrustedCertificate?) {
        self.expectedHost = expectedHost
        self.trustedCertificate = trustedCertificate
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard request.url?.scheme?.lowercased() == "https",
              request.url?.host?.caseInsensitiveCompare(expectedHost) == .orderedSame else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (
            URLSession.AuthChallengeDisposition,
            URLCredential?
        ) -> Void
    ) {
        handle(challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (
            URLSession.AuthChallengeDisposition,
            URLCredential?
        ) -> Void
    ) {
        // TLS challenges for data tasks are delivered here, rather than to the
        // session-level callback used by WebKit's navigation challenge.
        handle(challenge, completionHandler: completionHandler)
    }

    private func handle(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (
            URLSession.AuthChallengeDisposition,
            URLCredential?
        ) -> Void
    ) {
        let protectionSpace = challenge.protectionSpace
        guard protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trustedCertificate,
              protectionSpace.host.caseInsensitiveCompare(trustedCertificate.host) == .orderedSame,
              let serverTrust = protectionSpace.serverTrust,
              PortalCertificateFingerprint.sha256(of: serverTrust) == trustedCertificate.fingerprint else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

private enum PortalDownloadError: LocalizedError {
    case invalidResponse
    case responseTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The portal returned an invalid connection-file response."
        case .responseTooLarge:
            "The portal connection file exceeded the allowed size."
        }
    }
}
