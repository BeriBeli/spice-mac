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

        XCTAssertEqual(
            appSource.components(separatedBy: "SpiceCommands()").count - 1,
            1,
            "Registering the same Commands value on multiple WindowGroups creates duplicate macOS menus."
        )
    }

    func testLauncherIsSingletonAndDoesNotAutomaticallyOpenFilePicker() throws {
        let appSource = try source("Sources/Maspice/MaspiceApp.swift")
        let launcherSource = try source("Sources/Maspice/LauncherView.swift")

        XCTAssertTrue(appSource.contains("Window(\"Maspice\", id: \"launcher\")"))
        XCTAssertFalse(appSource.contains("WindowGroup(\"Maspice\", id: \"launcher\")"))
        XCTAssertFalse(launcherSource.contains("offerOpenPanelIfNeeded"))
        XCTAssertTrue(launcherSource.contains("dismissWindow(id: \"launcher\")"))
        XCTAssertTrue(launcherSource.contains("private func openSession(_ request: SessionRequest)"))
        XCTAssertTrue(appSource.contains(".restorationBehavior(.disabled)"))
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
        XCTAssertTrue(portalSource.contains("cancelPendingWork"))
        XCTAssertFalse(portalSource.contains("NSViewRepresentable"))
        XCTAssertFalse(portalSource.contains("WKWebView("))
    }
}
