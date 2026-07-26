// SPDX-License-Identifier: MIT
import AppKit
import Observation

/// The narrow application-delegate edge that SwiftUI does not own: Finder and
/// `open` deliver document URLs through `NSApplicationDelegate`.
@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var pendingRequests: [SessionRequest] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let commandLineRequests = CommandLine.arguments.dropFirst()
            .filter { $0.hasSuffix(".vv") }
            .map { SessionRequest(url: URL(fileURLWithPath: $0)) }
        pendingRequests.append(contentsOf: commandLineRequests)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingRequests.append(contentsOf: urls.map { SessionRequest(url: $0) })
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func drainPendingRequests() -> [SessionRequest] {
        defer { pendingRequests.removeAll() }
        return pendingRequests
    }

}
