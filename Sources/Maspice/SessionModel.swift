// SPDX-License-Identifier: MIT
import AppKit
import Observation
import SpiceController
import SpiceSessionLogic
import SwiftSpice
import VVConfig

@MainActor
@Observable
final class SessionModel {
    let sourceURL: URL
    let client: SpiceClient?
    let baseTitle: String
    let prefersFullscreen: Bool

    private(set) var status: SpiceClient.Status = .idle
    private(set) var parseFailure: String?
    private(set) var isInputAvailable = false
    private(set) var shouldReturnToLauncher = false
    private(set) var terminalFailureMessage: String?

    @ObservationIgnored private var lifecycle = SessionLifecycle()
    @ObservationIgnored private var shouldTrashAfterStart = false
    @ObservationIgnored private var shouldRemoveAfterStart = false

    init(request: SessionRequest) {
        sourceURL = request.url

        do {
            let config = try VVConfig(contentsOf: request.url)
            let parameters = try SpiceConnectionParameters(from: config)
            let client = SpiceClient(parameters: parameters)
            client.shareClipboard = Preferences.shareClipboard

            self.client = client
            baseTitle = client.title ?? request.url.deletingPathExtension().lastPathComponent
            prefersFullscreen = client.prefersFullscreen
            shouldTrashAfterStart = config.shouldDeleteThisFile(
                fallback: Preferences.trashConnectionFileAfterUse
            )
            shouldRemoveAfterStart = request.removesFileAfterStart

            observe(client)
        } catch {
            client = nil
            baseTitle = request.url.deletingPathExtension().lastPathComponent
            prefersFullscreen = false
            parseFailure = String(describing: error)
            terminalFailureMessage = "Could not open “\(request.url.lastPathComponent)”\n\(error)"
            shouldReturnToLauncher = true
            if request.removesFileAfterStart, request.url.isFileURL {
                try? FileManager.default.removeItem(at: request.url)
            }
        }
    }

    var windowTitle: String {
        switch status {
        case .connecting: "\(baseTitle) — Connecting…"
        case .disconnected: "\(baseTitle) — Disconnected"
        case .failed: "\(baseTitle) — Failed"
        case .connected, .idle: baseTitle
        }
    }

    var statusMessage: String? {
        if let parseFailure {
            return "Could not open “\(sourceURL.lastPathComponent)”\n\(parseFailure)"
        }
        return switch status {
        case .idle: nil
        case .connecting: "Connecting…"
        case .connected: nil
        case .disconnected: "Disconnected.\nReopen the .vv file to connect again."
        case let .failed(message): SessionFailureMessage.status(from: message)
        }
    }

    func start() {
        guard let client, lifecycle.start() else { return }
        client.connect()
        if shouldRemoveAfterStart {
            removeConnectionFile()
        } else if shouldTrashAfterStart {
            trashConnectionFile()
        }
    }

    func stop() {
        guard lifecycle.stop() else { return }
        client?.disconnect()
        isInputAvailable = false
    }

    func setClipboardSharing(_ enabled: Bool) {
        client?.shareClipboard = enabled
    }

    func sendCtrlAltDelete() {
        client?.sendCtrlAltDelete()
    }

    func releaseAllInput() {
        _ = NSApp.sendAction(
            NSSelectorFromString("releaseSpicePointerCapture:"),
            to: nil,
            from: nil
        )
        client?.releaseAllInput()
    }

    func requestResolution(width: Int, height: Int) {
        client?.requestResolution(width: width, height: height)
    }

    private func handleTerminalStatus(_ status: SpiceClient.Status) {
        let failureMessage: String?
        let needsDisconnect: Bool
        switch status {
        case .disconnected:
            failureMessage = nil
            needsDisconnect = false
        case let .failed(message):
            failureMessage = message
            needsDisconnect = true
        case .idle, .connecting, .connected:
            return
        }

        guard lifecycle.connectionDidTerminate() else { return }
        if needsDisconnect { client?.disconnect() }
        isInputAvailable = false
        terminalFailureMessage = failureMessage
        shouldReturnToLauncher = true
    }

    private func observe(_ client: SpiceClient) {
        withObservationTracking {
            _ = client.status
            _ = client.isInputAvailable
        } onChange: { [weak self, weak client] in
            Task { @MainActor in
                guard let self, let client, self.client === client else { return }
                self.status = client.status
                self.isInputAvailable = client.isInputAvailable
                self.handleTerminalStatus(self.status)
                self.observe(client)
            }
        }
    }

    private func trashConnectionFile() {
        guard sourceURL.isFileURL, getuid() != 0 else { return }
        NSWorkspace.shared.recycle([sourceURL]) { _, error in
            if let error {
                NSLog("Maspice: could not move \(self.sourceURL.lastPathComponent) to Trash: \(error.localizedDescription)")
            }
        }
    }

    private func removeConnectionFile() {
        guard sourceURL.isFileURL else { return }
        do {
            try FileManager.default.removeItem(at: sourceURL)
        } catch {
            NSLog("Maspice: could not remove temporary \(sourceURL.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
