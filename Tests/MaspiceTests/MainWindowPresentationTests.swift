import AppKit
import Testing
@testable import Maspice

@MainActor
struct MainWindowPresentationTests {
    @Test(arguments: [false, true])
    func returningFromPortalRestoresLauncherSizeInsteadOfPreviousUserSize(resizePortal: Bool) async throws {
        _ = NSApplication.shared
        // Exercise real AppKit zoom/restore geometry without presenting a test
        // window or touching the user's application windows.
        let window = OffscreenPresentationWindow(
            contentRect: NSRect(x: 100, y: 100, width: 520, height: 300),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let coordinator = MainWindowPresentationBridge.Coordinator(destination: .launcher)
        defer { coordinator.stop(); window.close() }
        let resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main
        ) { [weak window] _ in
            MainActor.assumeIsolated {
                guard let window else { return }
                window.observedContentSizes.append(window.contentRect(forFrameRect: window.frame).size)
            }
        }
        defer { NotificationCenter.default.removeObserver(resizeObserver) }
        coordinator.attach(to: window)
        await settlePresentation()
        let initialScreen = try #require(window.screen)
        #expect(abs(window.frame.midX - initialScreen.visibleFrame.midX) < 1)
        #expect(abs(window.frame.midY - initialScreen.visibleFrame.midY) < 1)

        for _ in 0..<2 {
            window.setContentSize(NSSize(width: 800, height: 500))
            coordinator.update(destination: .portal)
            await settlePresentation()
            try #require(window.isZoomed)
            if resizePortal { window.setContentSize(NSSize(width: 900, height: 600)) }

            let portalScreen = try #require(window.screen)
            window.observedContentSizes.removeAll()
            coordinator.update(destination: .launcher)
            await settlePresentation()
            #expect(window.contentRect(forFrameRect: window.frame).size == NSSize(width: 520, height: 300))
            #expect(!window.isZoomed)
            #expect(abs(window.frame.midX - portalScreen.visibleFrame.midX) < 1)
            #expect(abs(window.frame.midY - portalScreen.visibleFrame.midY) < 1)
            #expect(!window.observedContentSizes.isEmpty)
            #expect(window.observedContentSizes.allSatisfy { $0 == NSSize(width: 520, height: 300) })
        }

        // Returning home sets the default once; later activation must not undo
        // a deliberate resize while the user stays on the launcher.
        window.setContentSize(NSSize(width: 700, height: 400))
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        await settlePresentation()
        #expect(window.contentRect(forFrameRect: window.frame).size == NSSize(width: 700, height: 400))

    }

    private func settlePresentation() async {
        // The production bridge deliberately applies after SwiftUI's update.
        for _ in 0..<10 { await Task.yield() }
    }
}

@MainActor private final class OffscreenPresentationWindow: NSWindow {
    var observedContentSizes: [NSSize] = []
    override var isVisible: Bool { true }
}
