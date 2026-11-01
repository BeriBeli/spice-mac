// SPDX-License-Identifier: MIT
import AppKit
import SpiceController
import SwiftSpice
import SwiftUI

/// SwiftSpice owns the Metal/AppKit desktop surface. This view only adds the
/// narrow NSWindow lifecycle bridge needed for focus release and guest resize.
struct SwiftSpiceDesktop: View {
    let desktop: SpiceDesktopSource
    let onInput: @MainActor @Sendable (SpiceClientInput) -> Void
    let model: SessionModel

    var body: some View {
        SpiceDesktopView(
            desktop: desktop,
            onInput: onInput
        )
        .background {
            SpiceWindowBridge(
                dynamicResolutionEnabled: model.client?.supportsDynamicResolution == true,
                onReleaseInput: model.releaseAllInput,
                onResolution: model.requestResolution(width:height:)
            )
            .frame(width: 0, height: 0)
        }
    }
}

private struct SpiceWindowBridge: NSViewRepresentable {
    let dynamicResolutionEnabled: Bool
    let onReleaseInput: @MainActor () -> Void
    let onResolution: @MainActor (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            dynamicResolutionEnabled: dynamicResolutionEnabled,
            onReleaseInput: onReleaseInput,
            onResolution: onResolution
        )
    }

    func makeNSView(context: Context) -> WindowProbeView {
        let view = WindowProbeView()
        view.onWindowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: WindowProbeView, context: Context) {
        context.coordinator.update(
            dynamicResolutionEnabled: dynamicResolutionEnabled,
            onReleaseInput: onReleaseInput,
            onResolution: onResolution
        )
        context.coordinator.attach(to: nsView.window)
    }

    static func dismantleNSView(_ nsView: WindowProbeView, coordinator: Coordinator) {
        nsView.onWindowChanged = nil
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var dynamicResolutionEnabled: Bool
        private var onReleaseInput: @MainActor () -> Void
        private var onResolution: @MainActor (Int, Int) -> Void

        init(
            dynamicResolutionEnabled: Bool,
            onReleaseInput: @escaping @MainActor () -> Void,
            onResolution: @escaping @MainActor (Int, Int) -> Void
        ) {
            self.dynamicResolutionEnabled = dynamicResolutionEnabled
            self.onReleaseInput = onReleaseInput
            self.onResolution = onResolution
        }

        func update(
            dynamicResolutionEnabled: Bool,
            onReleaseInput: @escaping @MainActor () -> Void,
            onResolution: @escaping @MainActor (Int, Int) -> Void
        ) {
            let shouldRetryResolution = dynamicResolutionEnabled && !self.dynamicResolutionEnabled
            self.dynamicResolutionEnabled = dynamicResolutionEnabled
            self.onReleaseInput = onReleaseInput
            self.onResolution = onResolution
            if shouldRetryResolution {
                requestCurrentResolution()
            }
        }

        func attach(to window: NSWindow?) {
            guard self.window !== window else { return }
            removeObservers()
            self.window = window
            guard let window else { return }
            window.acceptsMouseMovedEvents = true
            let center = NotificationCenter.default
            let names: [Notification.Name] = [
                NSWindow.didResignKeyNotification,
                NSWindow.didEndLiveResizeNotification,
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification,
                NSWindow.willCloseNotification,
            ]
            observers = names.map { name in
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.handle(name) }
                }
            }
            observers.append(center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleKeyWindowChange(NSApp.keyWindow)
                }
            })
        }

        func stop() {
            releaseWindowInput()
            removeObservers()
            window = nil
        }

        private func handle(_ name: Notification.Name) {
            switch name {
            case NSWindow.didResignKeyNotification, NSWindow.willCloseNotification:
                releaseWindowInput()
            case NSWindow.didEndLiveResizeNotification,
                 NSWindow.didEnterFullScreenNotification,
                 NSWindow.didExitFullScreenNotification:
                requestCurrentResolution()
            default:
                break
            }
        }

        private func handleKeyWindowChange(_ keyWindow: NSWindow?) {
            guard let keyWindow else { return }
            if keyWindow !== window {
                releaseWindowInput()
            }
        }

        private func releaseWindowInput() {
            if let window {
                Self.releasePointerCapture(in: window)
            }
            onReleaseInput()
        }

        private static func releasePointerCapture(in window: NSWindow) {
            let action = NSSelectorFromString("releaseSpicePointerCapture:")
            if let firstResponder = window.firstResponder,
               firstResponder.responds(to: action),
               NSApp.sendAction(action, to: firstResponder, from: nil) {
                return
            }
            guard let contentView = window.contentView else { return }
            var pendingViews = [contentView]
            while let view = pendingViews.popLast() {
                if view.responds(to: action),
                   NSApp.sendAction(action, to: view, from: nil) {
                    return
                }
                pendingViews.append(contentsOf: view.subviews)
            }
        }

        private func requestCurrentResolution() {
            guard dynamicResolutionEnabled,
                  let contentView = window?.contentView
            else { return }
            let size = contentView.convertToBacking(contentView.bounds).size
            let width = Int(size.width.rounded(.down))
            let height = Int(size.height.rounded(.down))
            guard width > 0, height > 0 else { return }
            onResolution(width, height)
        }

        private func removeObservers() {
            let center = NotificationCenter.default
            for observer in observers { center.removeObserver(observer) }
            observers.removeAll()
        }
    }
}

@MainActor
private final class WindowProbeView: NSView {
    var onWindowChanged: (@MainActor (NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChanged?(window)
    }
}
