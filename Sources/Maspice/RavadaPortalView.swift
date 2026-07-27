// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Observation
import Security
import SwiftUI
import VVConfig
import WebKit

/// macOS 26 native SwiftUI WebKit surface. `WebPage` owns navigation, cookies,
/// title, and progress; the navigation decider only intercepts `.vv` links.
struct RavadaPortalView: View {
    @State private var model: RavadaPortalModel

    init(
        url: URL,
        onConnectionFile: @escaping @MainActor (URL) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        _model = State(initialValue: RavadaPortalModel(
            initialURL: url,
            onConnectionFile: onConnectionFile,
            onError: onError))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(model.page.title.isEmpty ? "Ravada Portal" : model.page.title)
                    .lineLimit(1)

                Spacer()

                if model.page.isLoading {
                    ProgressView(value: model.page.estimatedProgress)
                        .frame(width: 120)
                }

                Button("Reload", systemImage: "arrow.clockwise") {
                    model.reload()
                }
                .labelStyle(.iconOnly)
            }
            .padding(10)

            Divider()

            WebView(model.page)
        }
        .task {
            model.loadInitialPage()
        }
        .onDisappear {
            model.cancelPendingWork()
        }
        .alert("Untrusted Portal Certificate", isPresented: trustPromptIsPresented) {
            Button("Cancel", role: .cancel) {
                model.resolvePortalTrust(.cancel)
            }
            Button("Trust Once") {
                model.resolvePortalTrust(.session)
            }
            Button("Always Trust") {
                model.resolvePortalTrust(.always)
            }
        } message: {
            Text("macOS cannot verify the certificate presented by \(model.challengedHost ?? "this portal"). “Always Trust” remembers this certificate; a changed certificate will be confirmed again.")
        }
    }

    private var trustPromptIsPresented: Binding<Bool> {
        Binding(
            get: { model.challengedHost != nil },
            set: { if !$0 { model.resolvePortalTrust(.cancel) } })
    }
}

@MainActor
@Observable
private final class RavadaPortalModel {
    let page: WebPage

    private let initialURL: URL
    private let trustCoordinator: PortalTrustCoordinator
    private let navigationDecider: RavadaNavigationDecider

    init(
        initialURL: URL,
        onConnectionFile: @escaping @MainActor (URL) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        self.initialURL = initialURL
        let trustCoordinator = PortalTrustCoordinator()
        self.trustCoordinator = trustCoordinator
        let dataStore = WKWebsiteDataStore.default()
        let decider = RavadaNavigationDecider(
            dataStore: dataStore,
            portalURL: initialURL,
            trustCoordinator: trustCoordinator,
            onConnectionFile: onConnectionFile,
            onError: onError)
        navigationDecider = decider
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = dataStore
        page = WebPage(configuration: configuration, navigationDecider: decider)
    }

    func loadInitialPage() {
        guard page.url == nil else { return }
        page.load(initialURL)
    }

    func reload() {
        page.reload()
    }

    var challengedHost: String? {
        trustCoordinator.challengedHost
    }

    func resolvePortalTrust(_ decision: PortalTrustDecision) {
        trustCoordinator.resolve(decision)
    }

    func cancelPendingWork() {
        navigationDecider.cancelDownload()
        trustCoordinator.cancelPendingChallenge()
    }
}

@MainActor
private final class RavadaNavigationDecider: WebPage.NavigationDeciding {
    private let dataStore: WKWebsiteDataStore
    private let portalHost: String
    private let trustCoordinator: PortalTrustCoordinator
    private let onConnectionFile: @MainActor (URL) -> Void
    private let onError: @MainActor (String) -> Void
    private var downloadInFlight = false
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
        guard Self.isUserInitiated(action.navigationType),
              isAllowedConnectionURL(action.request.url) else {
            onError("The portal tried to open an untrusted connection file. No connection was made.")
            return .cancel
        }
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
        if !downloadInFlight {
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
            onConnectionFile(destination)
        } catch is CancellationError {
            return
        } catch {
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

    private static func isUserInitiated(_ type: WKNavigationType) -> Bool {
        type == .linkActivated || type == .formSubmitted || type == .formResubmitted
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

@MainActor
@Observable
private final class PortalTrustCoordinator {
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

private enum PortalTrustDecision {
    case cancel
    case session
    case always
}

private struct PortalTrustedCertificate: Sendable {
    let host: String
    let fingerprint: String
}

private enum PortalCertificateFingerprint {
    static func sha256(of trust: SecTrust) -> String? {
        guard let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leafCertificate = certificates.first else { return nil }
        let certificateData = SecCertificateCopyData(leafCertificate) as Data
        return SHA256.hash(data: certificateData)
            .map { String(format: "%02x", $0) }
            .joined()
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
