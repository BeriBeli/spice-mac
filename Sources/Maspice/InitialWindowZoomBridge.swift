// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// Applies the native macOS Zoom action once after SwiftUI attaches the scene's
/// backing window. The scene's ideal-size policy remains SwiftUI-owned.
struct InitialWindowZoomBridge: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> InitialWindowZoomProbeView {
        let view = InitialWindowZoomProbeView()
        view.onWindowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: InitialWindowZoomProbeView, context: Context) {
        context.coordinator.attach(to: nsView.window)
    }

    static func dismantleNSView(_ nsView: InitialWindowZoomProbeView, coordinator: Coordinator) {
        nsView.onWindowChanged = nil
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var zoomTask: Task<Void, Never>?
        private var appliedZoom = false

        func attach(to window: NSWindow?) {
            guard self.window !== window else { return }
            detach()
            self.window = window
            guard let window else { return }
            observers = [
                NSWindow.didBecomeKeyNotification,
                NSWindow.didEndLiveResizeNotification,
            ].map { name in
                NotificationCenter.default.addObserver(
                    forName: name,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.scheduleZoom() }
                }
            }
            scheduleZoom()
        }

        func detach() {
            zoomTask?.cancel()
            zoomTask = nil
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers.removeAll()
            appliedZoom = false
            window = nil
        }

        private func scheduleZoom() {
            guard !appliedZoom, zoomTask == nil else { return }
            zoomTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, !Task.isCancelled else { return }
                zoomTask = nil
                guard let window, window.isVisible, window.isKeyWindow else { return }
                if !window.isZoomed {
                    window.zoom(nil)
                }
                appliedZoom = true
            }
        }
    }
}

@MainActor
final class InitialWindowZoomProbeView: NSView {
    var onWindowChanged: (@MainActor (NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChanged?(window)
    }
}
