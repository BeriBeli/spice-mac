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

        // SwiftUI builds scene commands after applicationDidFinishLaunching and
        // keeps an empty Format menu after its rich-text commands are removed.
        // Observe menu construction so the cleanup runs after those commands
        // arrive, without depending on an arbitrary launch delay.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidAddItem),
            name: NSMenu.didAddItemNotification,
            object: nil)
        DispatchQueue.main.async { [weak self] in
            self?.removeEmptyTopLevelMenus()
        }
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

    @objc private func menuDidAddItem() {
        DispatchQueue.main.async { [weak self] in
            self?.removeEmptyTopLevelMenus()
        }
    }

    private func removeEmptyTopLevelMenus() {
        guard let mainMenu = NSApp.mainMenu else { return }
        for item in mainMenu.items.reversed()
        where item.submenu?.items.isEmpty == true {
            mainMenu.removeItem(item)
        }
    }
}
