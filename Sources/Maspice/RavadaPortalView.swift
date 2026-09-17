// SPDX-License-Identifier: MIT
import Foundation
import Observation
import SwiftUI
import WebKit

/// macOS 26 native SwiftUI WebKit surface. `WebPage` owns navigation, cookies,
/// title, and progress; the navigation decider also repairs skewed login cookies.
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
        WebView(model.page)
            .navigationTitle(model.pageTitle)
            .navigationSubtitle(model.pageAddress)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button("Go Back", systemImage: "chevron.backward") {
                        model.goBack()
                    }
                    .disabled(!model.canGoBack)
                    .help("Go to the previous portal page")

                    Button("Go Forward", systemImage: "chevron.forward") {
                        model.goForward()
                    }
                    .disabled(!model.canGoForward)
                    .help("Go to the next portal page")
                }

                ToolbarItem(placement: .status) {
                    if model.isLoading {
                        ProgressView(value: model.isSubmitting ? nil : model.page.estimatedProgress)
                            .frame(width: 100)
                            .help(model.isSubmitting ? "Signing in to portal" : "Loading portal")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(
                        model.isLoading ? "Stop Loading" : "Reload",
                        systemImage: model.isLoading ? "xmark" : "arrow.clockwise"
                    ) {
                        model.reloadOrStop()
                    }
                    .help(model.isLoading ? "Stop loading this page" : "Reload this page")
                }
            }
        .overlay {
            if let failure = model.loadFailure {
                ContentUnavailableView {
                    Label("Could Not Load Portal", systemImage: "network.slash")
                } description: {
                    Text("Check your network connection and try opening the portal again.")
                    DisclosureGroup("Details") { Text(failure).textSelection(.enabled) }
                        .frame(maxWidth: 420)
                } actions: {
                    Button("Retry Portal") { model.retryPortal() }.keyboardShortcut(.defaultAction)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
            }
        }
        .task(id: model.observationID) {
            await model.observeNavigations()
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
final class RavadaPortalModel {
    let page: WebPage

    private let initialURL: URL
    private let trustCoordinator: PortalTrustCoordinator
    private let navigationDecider: RavadaNavigationDecider
    var loadFailure: String?
    var observationID = 0
    var isSubmitting: Bool { navigationDecider.loginCoordinator.isSubmitting }
    var isLoading: Bool { page.isLoading || isSubmitting }
    private var shouldOpenPortal = false
    private var hasRequestedInitialPage = false


    func observeNavigations() async {
        let events = page.navigations
        if shouldOpenPortal {
            shouldOpenPortal = false
            page.load(URLRequest(url: initialURL, cachePolicy: .reloadIgnoringLocalCacheData))
        } else {
            loadInitialPage()
        }
        do {
            for try await event in events {
                if Task.isCancelled { return }
                if event == .startedProvisionalNavigation { loadFailure = nil }
            }
        } catch {
            guard !Task.isCancelled else { return }
            if case WebPage.NavigationError.failedProvisionalNavigation(let underlying) = error {
                let failure = underlying as NSError
                // Stop, downloads, and intercepted login requests cancel WebKit
                // navigation deliberately; none indicates a network failure.
                if failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled {
                    observationID += 1
                    return
                }
                loadFailure = underlying.localizedDescription
            } else {
                loadFailure = error.localizedDescription
            }
            // A thrown event ends this subscription, not the WebPage. Reattach
            // before a subsequent toolbar action or website navigation starts.
            if case WebPage.NavigationError.pageClosed = error { return }
            observationID += 1
        }
    }

    func retryPortal() {
        loadFailure = nil
        shouldOpenPortal = true
        observationID += 1
    }

    init(
        initialURL: URL,
        dataStore: WKWebsiteDataStore = .default(),
        onConnectionFile: @escaping @MainActor (URL) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        self.initialURL = initialURL
        let trustCoordinator = PortalTrustCoordinator()
        self.trustCoordinator = trustCoordinator
        let decider = RavadaNavigationDecider(
            dataStore: dataStore,
            portalURL: initialURL,
            trustCoordinator: trustCoordinator,
            onConnectionFile: onConnectionFile,
            onError: onError)
        navigationDecider = decider
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = dataStore
        configuration.userContentController.addUserScript(PortalLoginCoordinator.captureScript)
        if let autofillHints = PortalAutofillHints.script(for: initialURL) {
            configuration.userContentController.addUserScript(autofillHints)
        }
        page = WebPage(configuration: configuration, navigationDecider: decider)
        decider.loginCoordinator.page = page
    }

    func loadInitialPage() {
        navigationDecider.prepareCookies()
        guard !Task.isCancelled else { return }
        guard !hasRequestedInitialPage else { return }
        hasRequestedInitialPage = true
        // The first response supplies the portal's clock; do not sample a stale
        // HTTP Date from the local response cache.
        page.load(URLRequest(url: initialURL, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    var pageTitle: String {
        page.title.isEmpty ? "Ravada Portal" : page.title
    }

    var portalURL: URL { initialURL }

    var pageAddress: String {
        page.url?.host() ?? initialURL.host() ?? initialURL.absoluteString
    }

    var canGoBack: Bool {
        !page.backForwardList.backList.isEmpty
    }

    var canGoForward: Bool {
        !page.backForwardList.forwardList.isEmpty
    }

    func goBack() {
        loadFailure = nil
        navigationDecider.loginCoordinator.cancel()
        guard let item = page.backForwardList.backList.last else { return }
        page.load(item)
    }

    func goForward() {
        loadFailure = nil
        navigationDecider.loginCoordinator.cancel()
        guard let item = page.backForwardList.forwardList.first else { return }
        page.load(item)
    }

    func reloadOrStop() {
        let wasLoading = isLoading
        loadFailure = nil
        navigationDecider.loginCoordinator.cancel()
        if wasLoading {
            page.stopLoading()
        } else if page.url == nil {
            // A failed first navigation leaves no history item to reload.
            page.load(URLRequest(url: initialURL, cachePolicy: .reloadIgnoringLocalCacheData))
        } else {
            page.reload()
        }
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
