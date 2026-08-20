// SPDX-License-Identifier: MIT
import Foundation
import Observation
import SwiftUI
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
                    if model.page.isLoading {
                        ProgressView(value: model.page.estimatedProgress)
                            .frame(width: 100)
                            .help("Loading portal")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(
                        model.page.isLoading ? "Stop Loading" : "Reload",
                        systemImage: model.page.isLoading ? "xmark" : "arrow.clockwise"
                    ) {
                        model.reloadOrStop()
                    }
                    .help(model.page.isLoading ? "Stop loading this page" : "Reload this page")
                }
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

    var pageTitle: String {
        page.title.isEmpty ? "Ravada Portal" : page.title
    }

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
        guard let item = page.backForwardList.backList.last else { return }
        page.load(item)
    }

    func goForward() {
        guard let item = page.backForwardList.forwardList.first else { return }
        page.load(item)
    }

    func reloadOrStop() {
        if page.isLoading {
            page.stopLoading()
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
