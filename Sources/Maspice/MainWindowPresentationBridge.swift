// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// SwiftUI owns the main window's destination. This narrow bridge only applies
/// the corresponding native Zoom or restore operation to the existing window.
struct MainWindowPresentationBridge: NSViewRepresentable {
    let destination: MainDestination

    func makeCoordinator() -> Coordinator {
        Coordinator(destination: destination)
    }

    func makeNSView(context: Context) -> MainWindowProbeView {
        let view = MainWindowProbeView()
        view.onWindowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: MainWindowProbeView, context: Context) {
        context.coordinator.update(destination: destination)
        context.coordinator.attach(to: nsView.window)
    }

    static func dismantleNSView(
        _ nsView: MainWindowProbeView,
        coordinator: Coordinator
    ) {
        nsView.onWindowChanged = nil
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        private weak var window: NSWindow?
        private var destination: MainDestination
        private var appliedDestination: MainDestination?
        private var presentationTask: Task<Void, Never>?
        private var observers: [NSObjectProtocol] = []

        init(destination: MainDestination) {
            self.destination = destination
        }

        func update(destination: MainDestination) {
            guard self.destination != destination else { return }
            self.destination = destination
            schedulePresentation()
        }

        func attach(to window: NSWindow?) {
            guard self.window !== window else { return }
            removeObservers()
            self.window = window
            appliedDestination = nil
            if let window {
                let center = NotificationCenter.default
                observers = [
                    NSWindow.didBecomeKeyNotification,
                    NSWindow.didExitFullScreenNotification,
                ].map { name in
                    center.addObserver(
                        forName: name,
                        object: window,
                        queue: .main
                    ) { [weak self] _ in
                        MainActor.assumeIsolated {
                            self?.schedulePresentation()
                        }
                    }
                }
            }
            schedulePresentation()
        }

        func stop() {
            presentationTask?.cancel()
            presentationTask = nil
            removeObservers()
            window = nil
        }

        private func schedulePresentation() {
            presentationTask?.cancel()
            presentationTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled else { return }
                self?.applyPresentation()
            }
        }

        private func applyPresentation() {
            guard let window, window.isVisible,
                  appliedDestination != destination else { return }

            if destination == .launcher,
               window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
                return
            }

            appliedDestination = destination
            switch destination {
            case .launcher:
                window.contentMinSize = NSSize(width: 520, height: 300)
                if window.isZoomed {
                    window.zoom(nil)
                } else {
                    window.setContentSize(NSSize(width: 520, height: 300))
                }
            case .portal:
                window.contentMinSize = NSSize(width: 900, height: 650)
                if !window.isZoomed {
                    window.zoom(nil)
                }
            }
        }

        private func removeObservers() {
            let center = NotificationCenter.default
            for observer in observers {
                center.removeObserver(observer)
            }
            observers.removeAll()
        }
    }
}

@MainActor
final class MainWindowProbeView: NSView {
    var onWindowChanged: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChanged?(window)
    }
}
