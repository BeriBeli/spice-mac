// SPDX-License-Identifier: MIT
import AppKit
import Combine
@preconcurrency import CocoaSpice
import Observation
import SpiceController
import SpiceSessionLogic
import VVConfig

struct USBDeviceItem: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let isConnected: Bool
}

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
    private(set) var usbDevices: [USBDeviceItem] = []
    private(set) var shouldReturnToLauncher = false
    private(set) var terminalFailureMessage: String?
    var usbError: String?

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var lifecycle = SessionLifecycle()
    @ObservationIgnored private var shouldTrashAfterStart = false
    @ObservationIgnored private var shouldRemoveAfterStart = false
    @ObservationIgnored private lazy var usbDelegate = USBDelegateProxy { [weak self] message in
        Task { @MainActor in
            self?.usbDidChange(message)
        }
    }

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
                fallback: Preferences.trashConnectionFileAfterUse)
            shouldRemoveAfterStart = request.removesFileAfterStart

            client.$status
                .receive(on: RunLoop.main)
                .sink { [weak self] status in
                    MainActor.assumeIsolated {
                        self?.status = status
                        if status == .connected {
                            self?.refreshUSBDevices()
                        } else {
                            self?.handleTerminalStatus(status)
                        }
                    }
                }
                .store(in: &cancellables)
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
        case .connecting: return "\(baseTitle) — Connecting…"
        case .disconnected: return "\(baseTitle) — Disconnected"
        case .failed: return "\(baseTitle) — Failed"
        case .connected, .idle: return baseTitle
        }
    }

    var statusMessage: String? {
        if let parseFailure {
            return "Could not open “\(sourceURL.lastPathComponent)”\n\(parseFailure)"
        }
        switch status {
        case .idle: return nil
        case .connecting: return "Connecting…"
        case .connected: return nil
        case .disconnected: return "Disconnected.\nOpen a fresh .vv file to reconnect."
        case .failed(let message): return "Connection failed.\n\(message)"
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
        cleanUpRuntimeState()
    }

    private func cleanUpRuntimeState() {
        client?.usbManager?.delegate = nil
        usbDevices.removeAll()
        isInputAvailable = false
    }

    private func handleTerminalStatus(_ status: SpiceClient.Status) {
        let failureMessage: String?
        let needsDisconnect: Bool
        switch status {
        case .disconnected:
            failureMessage = nil
            needsDisconnect = false
        case .failed(let message):
            failureMessage = "Connection failed.\n\(message)"
            needsDisconnect = true
        case .idle, .connecting, .connected:
            return
        }

        guard lifecycle.connectionDidTerminate() else { return }
        if needsDisconnect { client?.disconnect() }
        cleanUpRuntimeState()
        terminalFailureMessage = failureMessage
        shouldReturnToLauncher = true
    }

    func setClipboardSharing(_ enabled: Bool) {
        client?.shareClipboard = enabled
    }

    func setInputAvailable(_ available: Bool) {
        isInputAvailable = available
    }

    func refreshUSBDevices() {
        guard let usb = client?.usbManager else {
            usbDevices = []
            return
        }
        usb.delegate = usbDelegate
        usbDevices = usb.usbDevices.map { device in
            USBDeviceItem(
                id: Self.usbID(device),
                label: Self.usbLabel(device),
                isConnected: usb.isUsbDeviceConnected(device))
        }
    }

    func toggleUSBDevice(id: String) {
        guard let usb = client?.usbManager,
              let device = usb.usbDevices.first(where: { Self.usbID($0) == id }) else { return }

        if usb.isUsbDeviceConnected(device) {
            usb.disconnectUsbDevice(device) { [weak self] error in
                let message = error?.localizedDescription
                Task { @MainActor in self?.usbDidChange(message) }
            }
        } else {
            var message: NSString?
            guard usb.canRedirectUsbDevice(device, errorMessage: &message) else {
                usbError = (message as String?) ?? "This USB device cannot be redirected."
                return
            }
            usb.connectUsbDevice(device) { [weak self] error in
                let message = error?.localizedDescription
                Task { @MainActor in self?.usbDidChange(message) }
            }
        }
    }

    private func usbDidChange(_ message: String?) {
        if let message { usbError = message }
        refreshUSBDevices()
    }

    private func trashConnectionFile() {
        guard sourceURL.isFileURL, getuid() != 0 else { return }
        NSWorkspace.shared.recycle([sourceURL]) { _, error in
            if let error {
                NSLog("SpiceMac: could not move \(self.sourceURL.lastPathComponent) to Trash: \(error.localizedDescription)")
            }
        }
    }

    private func removeConnectionFile() {
        guard sourceURL.isFileURL else { return }
        do {
            try FileManager.default.removeItem(at: sourceURL)
        } catch {
            NSLog("SpiceMac: could not remove temporary \(sourceURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private static func usbID(_ device: CSUSBDevice) -> String {
        "\(device.usbBusNumber):\(device.usbPortNumber):\(device.usbVendorId):\(device.usbProductId):\(device.usbSerial ?? "")"
    }

    private static func usbLabel(_ device: CSUSBDevice) -> String {
        let name = device.name ?? device.usbProductName ?? "USB Device"
        return String(format: "%@ (%04lx:%04lx)", name, device.usbVendorId, device.usbProductId)
    }
}

private final class USBDelegateProxy: NSObject, CSUSBManagerDelegate, @unchecked Sendable {
    private let onChange: @Sendable (String?) -> Void

    init(onChange: @escaping @Sendable (String?) -> Void) {
        self.onChange = onChange
    }

    func spiceUsbManager(_ usbManager: CSUSBManager, deviceAttached device: CSUSBDevice) {
        onChange(nil)
    }

    func spiceUsbManager(_ usbManager: CSUSBManager, deviceRemoved device: CSUSBDevice) {
        onChange(nil)
    }

    func spiceUsbManager(_ usbManager: CSUSBManager, deviceError error: String, for device: CSUSBDevice) {
        onChange(error)
    }
}
