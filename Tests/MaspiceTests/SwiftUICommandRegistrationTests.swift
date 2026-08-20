import Foundation
import Testing

@Suite("SwiftUI architecture policies")
struct SwiftUICommandRegistrationTests {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8)
    }

    @Test func `Application registers Spice commands exactly once`() throws {
        let appSource = try source("Sources/Maspice/MaspiceApp.swift")
        let commandsSource = try source("Sources/Maspice/SessionCommands.swift")
        let updateCommandsSource = try source("Sources/Maspice/UpdateCommands.swift")

        #expect(
            appSource.components(separatedBy: "SpiceCommands(").count - 1 == 1,
            "Registering the same Commands value on multiple WindowGroups creates duplicate macOS menus."
        )
        #expect(commandsSource.contains("Button(\"Open Connection File…\")"))
        #expect(commandsSource.contains("CommandMenu(\"Session\")"))
        #expect(commandsSource.contains("Toggle(\"Show Diagnostics\""))
        #expect(commandsSource.contains("Button(\"Copy Diagnostics Summary\")"))
        #expect(commandsSource.contains("sessionActions?.setDiagnosticsVisible($0)"))
        #expect(commandsSource.contains("@Entry var sessionActions: FocusedSessionActions?"))
        #expect(!commandsSource.contains("FocusedSessionActionsKey"))
        #expect(!commandsSource.contains("CommandGroup(before: .toolbar)"))
        #expect(!commandsSource.contains("CommandGroup(before: .windowSize)"))
        #expect(commandsSource.contains("CommandGroup(after: .appInfo)"))
        #expect(commandsSource.contains("CheckForUpdatesCommand(updater: updater)"))
        #expect(commandsSource.contains("CommandGroup(replacing: .help)"))
        #expect(commandsSource.contains("Link(\"What's New\", destination: latestReleaseURL)"))
        #expect(commandsSource.contains("Link(\"Report an Issue…\", destination: newIssueURL)"))
        #expect(commandsSource.contains("https://github.com/BeriBeli/spice-mac/releases/latest"))
        #expect(commandsSource.contains("https://github.com/BeriBeli/spice-mac/issues/new/choose"))
        #expect(updateCommandsSource.contains("Button(\"Check for Updates…\""))
        #expect(updateCommandsSource.contains("\\.canCheckForUpdates"))
        #expect(updateCommandsSource.contains("@Observable"))
        #expect(updateCommandsSource.contains("@State private var viewModel"))
        #expect(!updateCommandsSource.contains("ObservableObject"))
        #expect(!commandsSource.contains("Share Clipboard with VM"))
        #expect(!commandsSource.contains("@AppStorage"))
    }

    @Test(arguments: ["saveItem", "importExport", "printItem", "textFormatting", "toolbar", "sidebar"])
    func `Unsupported command group remains removed`(_ placement: String) throws {
        let commandsSource = try source("Sources/Maspice/SessionCommands.swift")

        #expect(
            commandsSource.contains("CommandGroup(replacing: .\(placement)) {}"),
            "The unsupported \(placement) command group should be removed."
        )
    }

    @Test func `Session diagnostics are window-scoped and explicitly enabled`() throws {
        let sessionViewSource = try source("Sources/Maspice/SessionView.swift")
        let diagnosticsRootSource = try source("Sources/Maspice/SessionDiagnosticsView.swift")
        let diagnosticsSummarySource = try source("Sources/Maspice/SessionDiagnosticsSummary.swift")
        let diagnosticsMetricsSource = try source("Sources/Maspice/SessionDiagnosticsMetrics.swift")
        let diagnosticsSectionsSource = try source("Sources/Maspice/SessionDiagnosticsSections.swift")
        let diagnosticsViewSource = [
            diagnosticsRootSource,
            diagnosticsSummarySource,
            diagnosticsMetricsSource,
            diagnosticsSectionsSource,
        ].joined(separator: "\n")
        let launcherSource = try source("Sources/Maspice/LauncherView.swift")
        let applicationModelSource = try source("Sources/Maspice/ApplicationModel.swift")

        #expect(sessionViewSource.contains("@State private var showsDiagnostics = false"))
        #expect(sessionViewSource.contains(".inspector(isPresented: diagnosticsInspectorIsPresented)"))
        #expect(sessionViewSource.contains(".inspectorColumnWidth(min: 310, ideal: 360, max: 440)"))
        #expect(sessionViewSource.contains("private var diagnosticsInspectorIsPresented: Binding<Bool>"))
        #expect(sessionViewSource.contains("private struct SessionDiagnosticsInspector: View"))
        #expect(!sessionViewSource.contains("SessionDiagnosticsOverlay"))
        #expect(sessionViewSource.contains("systemImage: \"sidebar.trailing\""))
        #expect(sessionViewSource.contains("private struct SessionChangeObserver: View"))
        #expect(sessionViewSource.contains("@AppStorage(Preferences.shareClipboardKey)"))
        #expect(sessionViewSource.contains("client.diagnosticsMonitor"))
        #expect(sessionViewSource.contains("model.client?.setDiagnosticsEnabled(true)"))
        #expect(sessionViewSource.contains("model.client?.setDiagnosticsEnabled(false)"))
        #expect(sessionViewSource.contains("setDiagnosticsVisible(false)"))
        #expect(sessionViewSource.contains("retainSessionDiagnosticsSummary"))
        #expect(diagnosticsRootSource.contains("private struct SessionDiagnosticsContent: View"))
        #expect(!diagnosticsRootSource.contains("private var diagnosticsContent"))
        #expect(diagnosticsSummarySource.contains("extension SpiceClientDiagnosticsSnapshot"))
        #expect(!diagnosticsSummarySource.contains("struct SessionDiagnosticsSwiftSpiceMetrics"))
        #expect(diagnosticsMetricsSource.contains("struct SessionDiagnosticsSwiftSpiceMetrics"))
        #expect(diagnosticsSectionsSource.contains("struct SessionDiagnosticsInputSection: View"))
        #expect(diagnosticsSectionsSource.contains("struct SessionDiagnosticsRendererSection: View"))
        #expect(diagnosticsViewSource.contains("NSPasteboard.general"))
        #expect(launcherSource.contains("Copy Last Diagnostics"))
        #expect(applicationModelSource.contains("lastSessionDiagnosticsSummary"))
        #expect(diagnosticsViewSource.contains("Session Diagnostics"))
        #expect(diagnosticsViewSource.contains("Copy Summary"))
        #expect(diagnosticsViewSource.contains("Publisher submit / emit / client"))
        #expect(diagnosticsViewSource.contains("Framed-receive batch gap p95 / max"))
        #expect(diagnosticsViewSource.contains("Receive → surface ready p95 / max"))
        #expect(diagnosticsViewSource.contains("Surface ready → publisher p95 / max"))
        #expect(diagnosticsViewSource.contains("Publisher stale / evicted / pending"))
        #expect(diagnosticsViewSource.contains("Readbacks / pool exhausted / GPU errors"))
        #expect(diagnosticsViewSource.contains("VDAgent"))
        #expect(diagnosticsViewSource.contains("Monitor supported / requests / blocked"))
        #expect(diagnosticsViewSource.contains("never contain clipboard text"))
        #expect(diagnosticsViewSource.contains("agent_snapshot_counter_epoch"))
        #expect(diagnosticsViewSource.contains("agent_event_counter_epoch"))
        #expect(diagnosticsViewSource.contains(
            "Clipboard data / grab / request / release"
        ))
        #expect(diagnosticsViewSource.contains(
            "Manager clipboard failures / last category"
        ))
        #expect(diagnosticsViewSource.contains("Advanced video"))
        #expect(diagnosticsViewSource.contains("MJPEG only"))
        #expect(diagnosticsViewSource.contains("current >= baseline ? current - baseline : current"))
        #expect(diagnosticsViewSource.contains(
            "Mailbox and Metal counters expose later-stage coalescing and presentation"
        ))
        #expect(diagnosticsViewSource.contains(
            "receive timing begins only after ChannelConnection returns"
        ))
        #expect(!diagnosticsViewSource.contains("firstMetalGenerationDisableReason"))
        #expect(!diagnosticsViewSource.contains("FileHandle"))
        #expect(!diagnosticsViewSource.contains("Logger"))
        #expect(!diagnosticsViewSource.contains("write(to:"))
        #expect(!diagnosticsViewSource.contains(".background(.regularMaterial"))
        #expect(!diagnosticsViewSource.contains(".shadow("))
        #expect(!diagnosticsViewSource.contains("maxHeight: 400"))
    }

    @Test func `Settings use focused native tabs`() throws {
        let settingsSource = try [
            "Sources/Maspice/SettingsView.swift",
            "Sources/Maspice/GeneralSettingsView.swift",
            "Sources/Maspice/UpdateSettingsView.swift",
            "Sources/Maspice/PortalSettingsView.swift",
        ]
        .map(source)
        .joined(separator: "\n")

        #expect(settingsSource.contains("TabView"))
        #expect(settingsSource.contains("Label(\"General\", systemImage: \"gearshape\")"))
        #expect(settingsSource.contains("Label(\"Updates\", systemImage: \"arrow.triangle.2.circlepath\")"))
        #expect(settingsSource.contains("Label(\"Portal\", systemImage: \"globe\")"))
        #expect(settingsSource.contains("struct GeneralSettingsView: View"))
        #expect(settingsSource.contains("struct UpdateSettingsView: View"))
        #expect(settingsSource.contains("struct PortalSettingsView: View"))
        #expect(settingsSource.contains("let title: LocalizedStringResource"))
        #expect(settingsSource.contains("Automatically check for updates"))
        #expect(settingsSource.contains("Download updates automatically"))
        #expect(settingsSource.contains("No saved certificate for this portal."))
        #expect(settingsSource.contains("Preferences.ravadaPortalURL(from: ravadaPortalURL)"))
    }

    @Test func `Launcher is singleton and does not automatically open file picker`() throws {
        let appSource = try source("Sources/Maspice/MaspiceApp.swift")
        let appDelegateSource = try source("Sources/Maspice/AppDelegate.swift")
        let launcherSource = try source("Sources/Maspice/LauncherView.swift")

        #expect(appSource.contains("Window(\"Maspice\", id: \"launcher\")"))
        #expect(!appSource.contains("WindowGroup(\"Maspice\", id: \"launcher\")"))
        #expect(!launcherSource.contains("offerOpenPanelIfNeeded"))
        #expect(!launcherSource.contains("showsPortal"))
        #expect(!launcherSource.contains("RavadaPortalView("))
        #expect(launcherSource.contains("openWindow(id: \"portal\")"))
        #expect(launcherSource.contains("@Environment(\\.dismiss)"))
        #expect(launcherSource.contains("dismiss()"))
        #expect(!launcherSource.contains("dismissWindow(id: \"launcher\")"))
        #expect(launcherSource.contains("private func openSession(_ request: SessionRequest)"))
        #expect(appSource.contains(".restorationBehavior(.disabled)"))
        #expect(appSource.contains(".defaultLaunchBehavior(.suppressed)"))
        #expect(!appDelegateSource.contains("applicationDidBecomeActive"))
        #expect(appDelegateSource.contains("NSMenu.didAddItemNotification"))
        #expect(appDelegateSource.contains("removeEmptyTopLevelMenus()"))
        #expect(launcherSource.contains("authorizePortalPresentation()"))
        #expect(launcherSource.contains("authorizeSessionPresentation(request)"))
        #expect(launcherSource.contains("@State private var isDropTargeted = false"))
        #expect(launcherSource.contains(".dropDestination(for: URL.self)"))
        #expect(launcherSource.contains("urls.first(where: \\.isFileURL)"))
        #expect(launcherSource.contains("private struct LauncherContent: View"))
        #expect(launcherSource.contains("private struct LauncherHeader: View"))
        #expect(launcherSource.contains("private struct LauncherActions: View"))
        #expect(!launcherSource.contains(".onDrop("))
        #expect(!launcherSource.contains("loadDataRepresentation"))
        #expect(!launcherSource.contains("public.file-url"))
    }

    @Test func `Portal and session windows use native maximum placement`() throws {
        let appSource = try source("Sources/Maspice/MaspiceApp.swift")
        let portalWindowSource = try source("Sources/Maspice/RavadaPortalWindow.swift")
        let sessionViewSource = try source("Sources/Maspice/SessionView.swift")
        let sessionBridgeSource = try source("Sources/Maspice/SpiceDisplayRepresentable.swift")
        let zoomBridgeURL = repositoryRoot
            .appendingPathComponent("Sources/Maspice/InitialWindowZoomBridge.swift")

        #expect(appSource.contains("Window(\"Ravada Portal\", id: \"portal\")"))
        #expect(
            appSource.components(separatedBy: ".windowIdealSize(.maximum)").count - 1 == 2
        )
        #expect(
            appSource.components(separatedBy: ".defaultWindowPlacement").count - 1 == 2
        )
        #expect(
            appSource.components(separatedBy: "context.defaultDisplay.visibleRect.size").count - 1 == 2
        )
        #expect(!appSource.contains(".defaultSize(width: 1024, height: 768)"))
        #expect(!FileManager.default.fileExists(atPath: zoomBridgeURL.path))
        #expect(!portalWindowSource.contains("InitialWindowZoomBridge()"))
        #expect(portalWindowSource.contains("RavadaPortalView("))
        #expect(portalWindowSource.contains("@Environment(\\.dismiss)"))
        #expect(portalWindowSource.contains("dismiss()"))
        #expect(portalWindowSource.contains("activatePortalPresentation()"))
        #expect(portalWindowSource.contains("deactivatePortalPresentation()"))
        #expect(portalWindowSource.contains("authorizeSessionPresentation(request)"))
        #expect(portalWindowSource.contains("guard !isHandingOffConnection else { return }"))
        #expect(portalWindowSource.contains("onError: presentPortalError"))
        #expect(!portalWindowSource.contains("@State private var presentationWasAuthorized"))
        #expect(!sessionViewSource.contains("InitialWindowZoomBridge()"))
        #expect(sessionViewSource.contains("activateSessionPresentation(for: requestID)"))
        #expect(sessionViewSource.contains("deactivateSessionPresentation(for: requestID)"))
        #expect(!sessionViewSource.contains("@State private var presentationWasAuthorized"))
        #expect(sessionBridgeSource.contains("NSWindow.didBecomeKeyNotification"))
        #expect(!sessionBridgeSource.contains("window.zoom(nil)"))
        #expect(!sessionBridgeSource.contains("window.setContentSize"))
    }

    @Test func `Portal uses native SwiftUI WebView and intercepts connection files`() throws {
        let portalViewSource = try source("Sources/Maspice/RavadaPortalView.swift")
        let navigationSource = try source("Sources/Maspice/RavadaNavigationDecider.swift")
        let trustSource = try source("Sources/Maspice/PortalTrustCoordinator.swift")
        let portalSource = [portalViewSource, navigationSource, trustSource]
            .joined(separator: "\n")

        #expect(portalSource.contains("WebView(model.page)"))
        #expect(portalSource.contains("WebPage("))
        #expect(portalSource.contains("WebPage.NavigationDeciding"))
        #expect(portalSource.contains("decideAuthenticationChallengeDisposition"))
        #expect(portalSource.contains("caseInsensitiveCompare(portalHost)"))
        #expect(portalSource.contains("Trust Once"))
        #expect(portalSource.contains("Always Trust"))
        #expect(portalSource.contains("PortalCertificateFingerprint.sha256"))
        #expect(portalSource.contains("== trustedCertificate.fingerprint"))
        #expect(portalSource.contains("VVConfig.parse(contents)"))
        #expect(portalSource.contains("session.bytes(for: request)"))
        #expect(portalSource.contains("task: URLSessionTask"))
        #expect(portalSource.contains("isAllowedConnectionURL"))
        #expect(portalSource.contains("action.source.isMainFrame"))
        #expect(portalSource.contains("action.buttonNumber == 0"))
        #expect(portalSource.contains("cancelPendingWork"))
        #expect(portalSource.contains("connectionWasDelivered = true"))
        #expect(portalSource.contains("guard !connectionWasDelivered else { return .cancel }"))
        #expect(!portalSource.contains("NSViewRepresentable"))
        #expect(!portalSource.contains("WKWebView("))
        #expect(navigationSource.contains("final class RavadaNavigationDecider"))
        #expect(trustSource.contains("final class PortalTrustCoordinator"))
        #expect(!portalViewSource.contains("URLSession("))
        #expect(!portalViewSource.contains("SecTrust"))
    }

    @Test func `Portal uses native window toolbar and browser navigation`() throws {
        let portalSource = try source("Sources/Maspice/RavadaPortalView.swift")
        let portalWindowSource = try source("Sources/Maspice/RavadaPortalWindow.swift")

        #expect(portalWindowSource.contains("ToolbarItem(placement: .navigation)"))
        #expect(portalWindowSource.contains("Button(\"Back to Launcher\", systemImage: \"house\")"))
        #expect(portalWindowSource.contains("private func returnToLauncher()"))
        #expect(!portalWindowSource.contains("VStack(spacing: 0)"))
        #expect(!portalWindowSource.contains("Divider()"))

        #expect(portalSource.contains(".navigationTitle(model.pageTitle)"))
        #expect(portalSource.contains(".navigationSubtitle(model.pageAddress)"))
        #expect(portalSource.contains("ToolbarItemGroup(placement: .navigation)"))
        #expect(portalSource.contains("Button(\"Go Back\", systemImage: \"chevron.backward\")"))
        #expect(portalSource.contains("Button(\"Go Forward\", systemImage: \"chevron.forward\")"))
        #expect(portalSource.contains("ProgressView(value: model.page.estimatedProgress)"))
        #expect(portalSource.contains("page.load(item)"))
        #expect(portalSource.contains("page.stopLoading()"))
        #expect(portalSource.contains("page.reload()"))
        #expect(!portalSource.contains("VStack(spacing: 0)"))
        #expect(!portalSource.contains("Divider()"))
    }
}
