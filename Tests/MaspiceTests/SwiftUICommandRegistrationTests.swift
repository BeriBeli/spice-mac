import Foundation
import XCTest

final class SwiftUICommandRegistrationTests: XCTestCase {
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

    func testApplicationRegistersSpiceCommandsExactlyOnce() throws {
        let appSource = try source("Sources/Maspice/MaspiceApp.swift")
        let commandsSource = try source("Sources/Maspice/SessionCommands.swift")
        let updateCommandsSource = try source("Sources/Maspice/UpdateCommands.swift")

        XCTAssertEqual(
            appSource.components(separatedBy: "SpiceCommands(").count - 1,
            1,
            "Registering the same Commands value on multiple WindowGroups creates duplicate macOS menus."
        )
        XCTAssertTrue(commandsSource.contains("Button(\"Open Connection File…\")"))
        XCTAssertTrue(commandsSource.contains("CommandMenu(\"Session\")"))
        XCTAssertTrue(commandsSource.contains("Toggle(\"Show Diagnostics\""))
        XCTAssertTrue(commandsSource.contains("Button(\"Copy Diagnostics Summary\")"))
        XCTAssertTrue(commandsSource.contains("sessionActions?.setDiagnosticsVisible($0)"))
        XCTAssertTrue(commandsSource.contains("@Entry var sessionActions: FocusedSessionActions?"))
        XCTAssertFalse(commandsSource.contains("FocusedSessionActionsKey"))
        XCTAssertFalse(commandsSource.contains("CommandGroup(before: .toolbar)"))
        XCTAssertFalse(commandsSource.contains("CommandGroup(before: .windowSize)"))
        XCTAssertTrue(commandsSource.contains("CommandGroup(after: .appInfo)"))
        XCTAssertTrue(commandsSource.contains("CheckForUpdatesCommand(updater: updater)"))
        XCTAssertTrue(commandsSource.contains("CommandGroup(replacing: .help)"))
        XCTAssertTrue(commandsSource.contains("Link(\"What's New\", destination: latestReleaseURL)"))
        XCTAssertTrue(commandsSource.contains("Link(\"Report an Issue…\", destination: newIssueURL)"))
        XCTAssertTrue(commandsSource.contains("https://github.com/BeriBeli/spice-mac/releases/latest"))
        XCTAssertTrue(commandsSource.contains("https://github.com/BeriBeli/spice-mac/issues/new/choose"))
        XCTAssertTrue(updateCommandsSource.contains("Button(\"Check for Updates…\""))
        XCTAssertTrue(updateCommandsSource.contains("\\.canCheckForUpdates"))
        XCTAssertTrue(updateCommandsSource.contains("@Observable"))
        XCTAssertTrue(updateCommandsSource.contains("@State private var viewModel"))
        XCTAssertFalse(updateCommandsSource.contains("ObservableObject"))
        XCTAssertFalse(commandsSource.contains("Share Clipboard with VM"))
        XCTAssertFalse(commandsSource.contains("@AppStorage"))

        for placement in ["saveItem", "importExport", "printItem", "textFormatting", "toolbar", "sidebar"] {
            XCTAssertTrue(
                commandsSource.contains("CommandGroup(replacing: .\(placement)) {}"),
                "The unsupported \(placement) command group should be removed."
            )
        }
    }

    func testSessionDiagnosticsAreWindowScopedAndExplicitlyEnabled() throws {
        let sessionViewSource = try source("Sources/Maspice/SessionView.swift")
        let diagnosticsViewSource = try source("Sources/Maspice/SessionDiagnosticsView.swift")
        let launcherSource = try source("Sources/Maspice/LauncherView.swift")
        let applicationModelSource = try source("Sources/Maspice/ApplicationModel.swift")

        XCTAssertTrue(sessionViewSource.contains("@State private var showsDiagnostics = false"))
        XCTAssertTrue(sessionViewSource.contains("private struct SessionChangeObserver: View"))
        XCTAssertTrue(sessionViewSource.contains("@AppStorage(Preferences.shareClipboardKey)"))
        XCTAssertTrue(sessionViewSource.contains("client.diagnosticsMonitor"))
        XCTAssertTrue(sessionViewSource.contains("model.client?.setDiagnosticsEnabled(true)"))
        XCTAssertTrue(sessionViewSource.contains("model.client?.setDiagnosticsEnabled(false)"))
        XCTAssertTrue(sessionViewSource.contains("setDiagnosticsVisible(false)"))
        XCTAssertTrue(sessionViewSource.contains("retainSessionDiagnosticsSummary"))
        XCTAssertTrue(diagnosticsViewSource.contains("NSPasteboard.general"))
        XCTAssertTrue(launcherSource.contains("Copy Last Diagnostics"))
        XCTAssertTrue(applicationModelSource.contains("lastSessionDiagnosticsSummary"))
        XCTAssertTrue(diagnosticsViewSource.contains("Session Diagnostics"))
        XCTAssertTrue(diagnosticsViewSource.contains("Copy Summary"))
        XCTAssertTrue(diagnosticsViewSource.contains("Publisher submit / emit / client"))
        XCTAssertTrue(diagnosticsViewSource.contains("Framed-receive batch gap p95 / max"))
        XCTAssertTrue(diagnosticsViewSource.contains("Receive → surface ready p95 / max"))
        XCTAssertTrue(diagnosticsViewSource.contains("Surface ready → publisher p95 / max"))
        XCTAssertTrue(diagnosticsViewSource.contains("Publisher stale / evicted / pending"))
        XCTAssertTrue(diagnosticsViewSource.contains("Readbacks / pool exhausted / GPU errors"))
        XCTAssertTrue(diagnosticsViewSource.contains("VDAgent"))
        XCTAssertTrue(diagnosticsViewSource.contains("Monitor supported / requests / blocked"))
        XCTAssertTrue(diagnosticsViewSource.contains("never contain clipboard text"))
        XCTAssertTrue(diagnosticsViewSource.contains("agent_snapshot_counter_epoch"))
        XCTAssertTrue(diagnosticsViewSource.contains("agent_event_counter_epoch"))
        XCTAssertTrue(diagnosticsViewSource.contains(
            "Clipboard data / grab / request / release"
        ))
        XCTAssertTrue(diagnosticsViewSource.contains(
            "Manager clipboard failures / last category"
        ))
        XCTAssertTrue(diagnosticsViewSource.contains("Advanced video"))
        XCTAssertTrue(diagnosticsViewSource.contains("MJPEG only"))
        XCTAssertTrue(diagnosticsViewSource.contains("current >= baseline ? current - baseline : current"))
        XCTAssertTrue(diagnosticsViewSource.contains(
            "Mailbox and Metal counters expose later-stage coalescing and presentation"
        ))
        XCTAssertTrue(diagnosticsViewSource.contains(
            "receive timing begins only after ChannelConnection returns"
        ))
        XCTAssertFalse(diagnosticsViewSource.contains("firstMetalGenerationDisableReason"))
        XCTAssertFalse(diagnosticsViewSource.contains("FileHandle"))
        XCTAssertFalse(diagnosticsViewSource.contains("Logger"))
        XCTAssertFalse(diagnosticsViewSource.contains("write(to:"))
    }

    func testSettingsUseFocusedNativeTabs() throws {
        let settingsSource = try [
            "Sources/Maspice/SettingsView.swift",
            "Sources/Maspice/GeneralSettingsView.swift",
            "Sources/Maspice/UpdateSettingsView.swift",
            "Sources/Maspice/PortalSettingsView.swift",
        ]
        .map(source)
        .joined(separator: "\n")

        XCTAssertTrue(settingsSource.contains("TabView"))
        XCTAssertTrue(settingsSource.contains("Label(\"General\", systemImage: \"gearshape\")"))
        XCTAssertTrue(settingsSource.contains("Label(\"Updates\", systemImage: \"arrow.triangle.2.circlepath\")"))
        XCTAssertTrue(settingsSource.contains("Label(\"Portal\", systemImage: \"globe\")"))
        XCTAssertTrue(settingsSource.contains("struct GeneralSettingsView: View"))
        XCTAssertTrue(settingsSource.contains("struct UpdateSettingsView: View"))
        XCTAssertTrue(settingsSource.contains("struct PortalSettingsView: View"))
        XCTAssertTrue(settingsSource.contains("let title: LocalizedStringResource"))
        XCTAssertTrue(settingsSource.contains("Automatically check for updates"))
        XCTAssertTrue(settingsSource.contains("Download updates automatically"))
        XCTAssertTrue(settingsSource.contains("No saved certificate for this portal."))
        XCTAssertTrue(settingsSource.contains("Preferences.ravadaPortalURL(from: ravadaPortalURL)"))
    }

    func testLauncherIsSingletonAndDoesNotAutomaticallyOpenFilePicker() throws {
        let appSource = try source("Sources/Maspice/MaspiceApp.swift")
        let appDelegateSource = try source("Sources/Maspice/AppDelegate.swift")
        let launcherSource = try source("Sources/Maspice/LauncherView.swift")

        XCTAssertTrue(appSource.contains("Window(\"Maspice\", id: \"launcher\")"))
        XCTAssertFalse(appSource.contains("WindowGroup(\"Maspice\", id: \"launcher\")"))
        XCTAssertFalse(launcherSource.contains("offerOpenPanelIfNeeded"))
        XCTAssertFalse(launcherSource.contains("showsPortal"))
        XCTAssertFalse(launcherSource.contains("RavadaPortalView("))
        XCTAssertTrue(launcherSource.contains("openWindow(id: \"portal\")"))
        XCTAssertTrue(launcherSource.contains("@Environment(\\.dismiss)"))
        XCTAssertTrue(launcherSource.contains("dismiss()"))
        XCTAssertFalse(launcherSource.contains("dismissWindow(id: \"launcher\")"))
        XCTAssertTrue(launcherSource.contains("private func openSession(_ request: SessionRequest)"))
        XCTAssertTrue(appSource.contains(".restorationBehavior(.disabled)"))
        XCTAssertTrue(appSource.contains(".defaultLaunchBehavior(.suppressed)"))
        XCTAssertFalse(appDelegateSource.contains("applicationDidBecomeActive"))
        XCTAssertTrue(appDelegateSource.contains("NSMenu.didAddItemNotification"))
        XCTAssertTrue(appDelegateSource.contains("removeEmptyTopLevelMenus()"))
        XCTAssertTrue(launcherSource.contains("authorizePortalPresentation()"))
        XCTAssertTrue(launcherSource.contains("authorizeSessionPresentation(request)"))
    }

    func testPortalAndSessionWindowsStartZoomed() throws {
        let appSource = try source("Sources/Maspice/MaspiceApp.swift")
        let portalWindowSource = try source("Sources/Maspice/RavadaPortalWindow.swift")
        let zoomBridgeSource = try source("Sources/Maspice/InitialWindowZoomBridge.swift")
        let sessionViewSource = try source("Sources/Maspice/SessionView.swift")
        let sessionBridgeSource = try source("Sources/Maspice/SpiceDisplayRepresentable.swift")

        XCTAssertTrue(appSource.contains("Window(\"Ravada Portal\", id: \"portal\")"))
        XCTAssertEqual(
            appSource.components(separatedBy: ".windowIdealSize(.maximum)").count - 1,
            2
        )
        XCTAssertTrue(portalWindowSource.contains("InitialWindowZoomBridge()"))
        XCTAssertTrue(portalWindowSource.contains("RavadaPortalView("))
        XCTAssertTrue(portalWindowSource.contains("@Environment(\\.dismiss)"))
        XCTAssertTrue(portalWindowSource.contains("dismiss()"))
        XCTAssertTrue(portalWindowSource.contains("activatePortalPresentation()"))
        XCTAssertTrue(portalWindowSource.contains("deactivatePortalPresentation()"))
        XCTAssertTrue(portalWindowSource.contains("authorizeSessionPresentation(request)"))
        XCTAssertTrue(portalWindowSource.contains("guard !isHandingOffConnection else { return }"))
        XCTAssertTrue(portalWindowSource.contains("onError: presentPortalError"))
        XCTAssertFalse(portalWindowSource.contains("@State private var presentationWasAuthorized"))
        XCTAssertTrue(zoomBridgeSource.contains("NSWindow.didBecomeKeyNotification"))
        XCTAssertTrue(zoomBridgeSource.contains("window.zoom(nil)"))
        XCTAssertTrue(zoomBridgeSource.contains("window.isKeyWindow"))
        XCTAssertTrue(sessionViewSource.contains("InitialWindowZoomBridge()"))
        XCTAssertTrue(sessionViewSource.contains("activateSessionPresentation(for: requestID)"))
        XCTAssertTrue(sessionViewSource.contains("deactivateSessionPresentation(for: requestID)"))
        XCTAssertFalse(sessionViewSource.contains("@State private var presentationWasAuthorized"))
        XCTAssertTrue(sessionBridgeSource.contains("NSWindow.didBecomeKeyNotification"))
        XCTAssertFalse(sessionBridgeSource.contains("window.zoom(nil)"))
        XCTAssertFalse(sessionBridgeSource.contains("window.setContentSize"))
    }

    func testPortalUsesNativeSwiftUIWebViewAndInterceptsConnectionFiles() throws {
        let portalSource = try source("Sources/Maspice/RavadaPortalView.swift")

        XCTAssertTrue(portalSource.contains("WebView(model.page)"))
        XCTAssertTrue(portalSource.contains("WebPage("))
        XCTAssertTrue(portalSource.contains("WebPage.NavigationDeciding"))
        XCTAssertTrue(portalSource.contains("decideAuthenticationChallengeDisposition"))
        XCTAssertTrue(portalSource.contains("caseInsensitiveCompare(portalHost)"))
        XCTAssertTrue(portalSource.contains("Trust Once"))
        XCTAssertTrue(portalSource.contains("Always Trust"))
        XCTAssertTrue(portalSource.contains("PortalCertificateFingerprint.sha256"))
        XCTAssertTrue(portalSource.contains("== trustedCertificate.fingerprint"))
        XCTAssertTrue(portalSource.contains("VVConfig.parse(contents)"))
        XCTAssertTrue(portalSource.contains("session.bytes(for: request)"))
        XCTAssertTrue(portalSource.contains("task: URLSessionTask"))
        XCTAssertTrue(portalSource.contains("isAllowedConnectionURL"))
        XCTAssertTrue(portalSource.contains("action.source.isMainFrame"))
        XCTAssertTrue(portalSource.contains("action.buttonNumber == 0"))
        XCTAssertTrue(portalSource.contains("cancelPendingWork"))
        XCTAssertTrue(portalSource.contains("connectionWasDelivered = true"))
        XCTAssertTrue(portalSource.contains("guard !connectionWasDelivered else { return .cancel }"))
        XCTAssertFalse(portalSource.contains("NSViewRepresentable"))
        XCTAssertFalse(portalSource.contains("WKWebView("))
    }

    func testPortalUsesNativeWindowToolbarAndBrowserNavigation() throws {
        let portalSource = try source("Sources/Maspice/RavadaPortalView.swift")
        let portalWindowSource = try source("Sources/Maspice/RavadaPortalWindow.swift")

        XCTAssertTrue(portalWindowSource.contains("ToolbarItem(placement: .navigation)"))
        XCTAssertTrue(portalWindowSource.contains("Button(\"Back to Launcher\", systemImage: \"house\")"))
        XCTAssertTrue(portalWindowSource.contains("private func returnToLauncher()"))
        XCTAssertFalse(portalWindowSource.contains("VStack(spacing: 0)"))
        XCTAssertFalse(portalWindowSource.contains("Divider()"))

        XCTAssertTrue(portalSource.contains(".navigationTitle(model.pageTitle)"))
        XCTAssertTrue(portalSource.contains(".navigationSubtitle(model.pageAddress)"))
        XCTAssertTrue(portalSource.contains("ToolbarItemGroup(placement: .navigation)"))
        XCTAssertTrue(portalSource.contains("Button(\"Go Back\", systemImage: \"chevron.backward\")"))
        XCTAssertTrue(portalSource.contains("Button(\"Go Forward\", systemImage: \"chevron.forward\")"))
        XCTAssertTrue(portalSource.contains("ProgressView(value: model.page.estimatedProgress)"))
        XCTAssertTrue(portalSource.contains("page.load(item)"))
        XCTAssertTrue(portalSource.contains("page.stopLoading()"))
        XCTAssertTrue(portalSource.contains("page.reload()"))
        XCTAssertFalse(portalSource.contains("VStack(spacing: 0)"))
        XCTAssertFalse(portalSource.contains("Divider()"))
    }
}
