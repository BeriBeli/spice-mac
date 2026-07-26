// SPDX-License-Identifier: MIT
import AppKit
import Combine
@preconcurrency import CocoaSpice
import SpiceController
import SwiftUI

@MainActor
private protocol SpiceDisplayActionHandling: AnyObject {
    func sendCtrlAltDelete()
    func releaseCursor()
}

@MainActor
final class SpiceDisplayActionRouter {
    fileprivate weak var handler: (any SpiceDisplayActionHandling)?

    func sendCtrlAltDelete() { handler?.sendCtrlAltDelete() }
    func releaseCursor() { handler?.releaseCursor() }
}

/// The only view-level AppKit bridge in the SwiftUI application. The coordinator
/// owns the long-lived `MTKView`; SwiftUI owns the session and visible state.
struct SpiceDisplayRepresentable: NSViewRepresentable {
    let model: SessionModel
    let actionRouter: SpiceDisplayActionRouter

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> SpiceDisplayView {
        actionRouter.handler = context.coordinator
        return context.coordinator.displayView
    }

    func updateNSView(_ nsView: SpiceDisplayView, context: Context) {
        context.coordinator.attachWindow(nsView.window)
    }

    static func dismantleNSView(_ nsView: SpiceDisplayView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject {
        let displayView = SpiceDisplayView()

        private let model: SessionModel
        private var cancellables = Set<AnyCancellable>()
        private weak var observedWindow: NSWindow?
        private var windowObservers: [NSObjectProtocol] = []
        private var stopped = false

        init(model: SessionModel) {
            self.model = model
            super.init()
            displayView.onWindowChanged = { [weak self] window in
                self?.attachWindow(window)
            }
            wireClient()
        }

        private func wireClient() {
            guard let client = model.client else { return }

            client.onDisplayCreated = { [weak self] display in
                MainActor.assumeIsolated { self?.attachDisplay(display) }
            }
            client.onDisplayDestroyed = { [weak self] _ in
                MainActor.assumeIsolated { self?.displayView.detach() }
            }
            client.onInputAvailable = { [weak self] input in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.displayView.router.input = input
                    self.displayView.router.requestMouseMode(server: false)
                    self.displayView.window?.makeFirstResponder(self.displayView)
                    self.displayView.refreshCursorPresentation()
                    self.model.setInputAvailable(true)
                }
            }
            client.onInputUnavailable = { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.displayView.router.input = nil
                    self.displayView.refreshCursorPresentation()
                    self.model.setInputAvailable(false)
                }
            }

            client.$agentConnected
                .receive(on: RunLoop.main)
                .sink { [weak self] connected in
                    MainActor.assumeIsolated {
                        if connected { self?.requestResolutionForCurrentSize() }
                    }
                }
                .store(in: &cancellables)
        }

        private func attachDisplay(_ display: CSDisplay) {
            guard !stopped else { return }
            displayView.attachDisplay(display)
            resizeWindowToDisplay(display.displaySize)
            displayView.window?.makeFirstResponder(displayView)
            if model.prefersFullscreen,
               displayView.window?.styleMask.contains(.fullScreen) == false {
                displayView.window?.toggleFullScreen(nil)
            }
        }

        func attachWindow(_ window: NSWindow?) {
            guard !stopped, observedWindow !== window else { return }
            removeWindowObservers()
            observedWindow = window
            guard let window else { return }

            window.acceptsMouseMovedEvents = true
            window.initialFirstResponder = displayView

            let center = NotificationCenter.default
            let names: [Notification.Name] = [
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
                NSWindow.didEndLiveResizeNotification,
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification,
                NSWindow.willCloseNotification,
            ]
            windowObservers = names.map { name in
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    let eventName = note.name
                    MainActor.assumeIsolated { self?.handleWindowNotification(eventName) }
                }
            }
        }

        private func handleWindowNotification(_ name: Notification.Name) {
            switch name {
            case NSWindow.didBecomeKeyNotification:
                displayView.window?.makeFirstResponder(displayView)
                displayView.refreshCursorPresentation()
                model.refreshUSBDevices()
            case NSWindow.didResignKeyNotification:
                displayView.router.releaseAll()
                displayView.refreshCursorPresentation()
                displayView.restoreSystemCursor()
            case NSWindow.didEndLiveResizeNotification,
                 NSWindow.didEnterFullScreenNotification,
                 NSWindow.didExitFullScreenNotification:
                requestResolutionForCurrentSize()
            case NSWindow.willCloseNotification:
                stop()
            default:
                break
            }
        }

        private func resizeWindowToDisplay(_ size: CGSize) {
            guard size.width > 1, size.height > 1,
                  let window = displayView.window,
                  !window.styleMask.contains(.fullScreen) else { return }
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame.size ?? size
            let scale = min(1, min(visible.width / size.width, visible.height / size.height))
            window.setContentSize(CGSize(
                width: floor(size.width * scale),
                height: floor(size.height * scale)))
            window.center()
        }

        private func requestResolutionForCurrentSize() {
            guard model.client?.supportsDynamicResolution == true,
                  let display = displayView.attachedDisplay else { return }
            display.requestResolution(displayView.convertToBacking(displayView.bounds))
        }

        fileprivate func sendCtrlAltDelete() {
            guard let input = displayView.router.input else { return }
            let combo: [Int32] = [0x1D, 0x38, 0x153]
            for code in combo { input.send(.press, code: code) }
            for code in combo.reversed() { input.send(.release, code: code) }
        }

        fileprivate func releaseCursor() {
            displayView.router.releaseAll()
        }

        func stop() {
            guard !stopped else { return }
            stopped = true
            removeWindowObservers()
            displayView.router.releaseAll()
            displayView.restoreSystemCursor()
            displayView.detach()
            displayView.onWindowChanged = nil
            model.client?.onDisplayCreated = nil
            model.client?.onDisplayDestroyed = nil
            model.client?.onInputAvailable = nil
            model.client?.onInputUnavailable = nil
            model.stop()
        }

        private func removeWindowObservers() {
            let center = NotificationCenter.default
            for observer in windowObservers { center.removeObserver(observer) }
            windowObservers.removeAll()
        }
    }
}

extension SpiceDisplayRepresentable.Coordinator: SpiceDisplayActionHandling {}
