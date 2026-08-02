// SPDX-License-Identifier: MIT
import AppKit
import SpiceController
import SwiftSpice
import SwiftUI

/// SwiftSpice owns the Metal/AppKit desktop surface. This view only adds the
/// narrow NSWindow lifecycle bridge needed for focus release and guest resize.
struct SwiftSpiceDesktop: View {
    @ObservedObject var client: SpiceClient
    let model: SessionModel

    var body: some View {
        SpiceDesktopView(
            frame: client.frame,
            cursor: client.cursor,
            pointerMode: client.pointerMode,
            onInput: client.submit(_:)
        )
        .background {
            SpiceWindowBridge(
                prefersFullscreen: model.prefersFullscreen,
                onReleaseInput: model.releaseAllInput,
                onResolution: model.requestResolution(width:height:)
            )
            .frame(width: 0, height: 0)
        }
    }
}

private struct SpiceWindowBridge: NSViewRepresentable {
    let prefersFullscreen: Bool
    let onReleaseInput: @MainActor () -> Void
    let onResolution: @MainActor (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            prefersFullscreen: prefersFullscreen,
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
            prefersFullscreen: prefersFullscreen,
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
        private var prefersFullscreen: Bool
        private var onReleaseInput: @MainActor () -> Void
        private var onResolution: @MainActor (Int, Int) -> Void
        private var appliedFullscreen = false
        private var initialPolicyTask: Task<Void, Never>?

        init(
            prefersFullscreen: Bool,
            onReleaseInput: @escaping @MainActor () -> Void,
            onResolution: @escaping @MainActor (Int, Int) -> Void
        ) {
            self.prefersFullscreen = prefersFullscreen
            self.onReleaseInput = onReleaseInput
            self.onResolution = onResolution
        }

        func update(
            prefersFullscreen: Bool,
            onReleaseInput: @escaping @MainActor () -> Void,
            onResolution: @escaping @MainActor (Int, Int) -> Void
        ) {
            self.prefersFullscreen = prefersFullscreen
            self.onReleaseInput = onReleaseInput
            self.onResolution = onResolution
            scheduleInitialWindowPolicy()
        }

        func attach(to window: NSWindow?) {
            guard self.window !== window else {
                scheduleInitialWindowPolicy()
                return
            }
            removeObservers()
            self.window = window
            guard let window else { return }
            window.acceptsMouseMovedEvents = true
            let center = NotificationCenter.default
            let names: [Notification.Name] = [
                NSWindow.didBecomeKeyNotification,
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
            scheduleInitialWindowPolicy()
        }

        func stop() {
            onReleaseInput()
            initialPolicyTask?.cancel()
            initialPolicyTask = nil
            removeObservers()
            window = nil
        }

        private func handle(_ name: Notification.Name) {
            switch name {
            case NSWindow.didBecomeKeyNotification:
                scheduleInitialWindowPolicy()
            case NSWindow.didResignKeyNotification, NSWindow.willCloseNotification:
                onReleaseInput()
            case NSWindow.didEndLiveResizeNotification,
                 NSWindow.didEnterFullScreenNotification,
                 NSWindow.didExitFullScreenNotification:
                scheduleInitialWindowPolicy()
                requestCurrentResolution()
            default:
                break
            }
        }

        private func applyInitialWindowPolicy() {
            guard let window, window.isVisible else { return }
            if prefersFullscreen, !appliedFullscreen,
               !window.styleMask.contains(.fullScreen) {
                appliedFullscreen = true
                window.toggleFullScreen(nil)
            }
        }

        private func scheduleInitialWindowPolicy() {
            guard initialPolicyTask == nil, prefersFullscreen, !appliedFullscreen else { return }
            initialPolicyTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, !Task.isCancelled else { return }
                initialPolicyTask = nil
                applyInitialWindowPolicy()
            }
        }

        private func requestCurrentResolution() {
            guard let contentView = window?.contentView else { return }
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
