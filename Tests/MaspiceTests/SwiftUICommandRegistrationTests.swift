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
        XCTAssertFalse(commandsSource.contains("Share Clipboard with VM"))
        XCTAssertFalse(commandsSource.contains("@AppStorage"))

        for placement in ["saveItem", "importExport", "printItem", "textFormatting", "toolbar", "sidebar"] {
            XCTAssertTrue(
                commandsSource.contains("CommandGroup(replacing: .\(placement)) {}"),
                "The unsupported \(placement) command group should be removed."
            )
        }
    }

    func testSettingsUseFocusedNativeTabs() throws {
        let settingsSource = try source("Sources/Maspice/SettingsView.swift")

        XCTAssertTrue(settingsSource.contains("TabView"))
        XCTAssertTrue(settingsSource.contains("Label(\"General\", systemImage: \"gearshape\")"))
        XCTAssertTrue(settingsSource.contains("Label(\"Updates\", systemImage: \"arrow.triangle.2.circlepath\")"))
        XCTAssertTrue(settingsSource.contains("Label(\"Portal\", systemImage: \"globe\")"))
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
}
