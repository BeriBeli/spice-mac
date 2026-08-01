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
                displaySize: client.frame.map {
                    CGSize(width: $0.width, height: $0.height)
                },
                prefersFullscreen: model.prefersFullscreen,
                onReleaseInput: model.releaseAllInput,
                onResolution: model.requestResolution(width:height:)
            )
            .frame(width: 0, height: 0)
        }
    }
}

private struct SpiceWindowBridge: NSViewRepresentable {
    let displaySize: CGSize?
    let prefersFullscreen: Bool
    let onReleaseInput: @MainActor () -> Void
    let onResolution: @MainActor (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            displaySize: displaySize,
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
            displaySize: displaySize,
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
        private var displaySize: CGSize?
        private var prefersFullscreen: Bool
        private var onReleaseInput: @MainActor () -> Void
        private var onResolution: @MainActor (Int, Int) -> Void
        private var appliedInitialDisplaySize = false
        private var appliedFullscreen = false

        init(
            displaySize: CGSize?,
            prefersFullscreen: Bool,
            onReleaseInput: @escaping @MainActor () -> Void,
            onResolution: @escaping @MainActor (Int, Int) -> Void
        ) {
            self.displaySize = displaySize
            self.prefersFullscreen = prefersFullscreen
            self.onReleaseInput = onReleaseInput
            self.onResolution = onResolution
        }

        func update(
            displaySize: CGSize?,
            prefersFullscreen: Bool,
            onReleaseInput: @escaping @MainActor () -> Void,
            onResolution: @escaping @MainActor (Int, Int) -> Void
        ) {
            self.displaySize = displaySize
            self.prefersFullscreen = prefersFullscreen
            self.onReleaseInput = onReleaseInput
            self.onResolution = onResolution
            applyInitialWindowPolicy()
        }

        func attach(to window: NSWindow?) {
            guard self.window !== window else {
                applyInitialWindowPolicy()
                return
            }
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
            applyInitialWindowPolicy()
        }

        func stop() {
            onReleaseInput()
            removeObservers()
            window = nil
        }

        private func handle(_ name: Notification.Name) {
            switch name {
            case NSWindow.didResignKeyNotification, NSWindow.willCloseNotification:
                onReleaseInput()
            case NSWindow.didEndLiveResizeNotification,
                 NSWindow.didEnterFullScreenNotification,
                 NSWindow.didExitFullScreenNotification:
                requestCurrentResolution()
            default:
                break
            }
        }

        private func applyInitialWindowPolicy() {
            guard let window else { return }
            if !appliedInitialDisplaySize,
               let displaySize,
               displaySize.width > 1,
               displaySize.height > 1,
               !window.styleMask.contains(.fullScreen) {
                let visible = (window.screen ?? NSScreen.main)?.visibleFrame.size ?? displaySize
                let scale = min(1, min(visible.width / displaySize.width, visible.height / displaySize.height))
                window.setContentSize(CGSize(
                    width: floor(displaySize.width * scale),
                    height: floor(displaySize.height * scale)
                ))
                window.center()
                appliedInitialDisplaySize = true
            }
            if prefersFullscreen, !appliedFullscreen,
               !window.styleMask.contains(.fullScreen) {
                appliedFullscreen = true
                window.toggleFullScreen(nil)
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
