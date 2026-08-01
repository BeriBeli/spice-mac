// SPDX-License-Identifier: MIT
import SwiftSpice

/// Serializes AppKit-produced input before it crosses the SwiftSpice actor boundary.
/// Key/button edges are lossless; adjacent pointer updates are coalesced.
@MainActor
final class OrderedSpiceInputPump {
    private let send: @Sendable (SpiceClientInput) async throws -> Void
    private let onFailure: @MainActor (SpiceError) -> Void
    private var pending: [SpiceClientInput] = []
    private var drainTask: Task<Void, Never>?
    private var pressedScanCodes: Set<UInt32> = []
    private var pressedButtons: [SpiceMouseButton] = []
    private var stopped = false

    init(session: SpiceSession, onFailure: @escaping @MainActor (SpiceError) -> Void) {
        self.send = { input in try await session.send(input) }
        self.onFailure = onFailure
    }

    init(
        send: @escaping @Sendable (SpiceClientInput) async throws -> Void,
        onFailure: @escaping @MainActor (SpiceError) -> Void
    ) {
        self.send = send
        self.onFailure = onFailure
    }

    func submit(_ input: SpiceClientInput) {
        guard !stopped else { return }
        updatePressedState(for: input)
        enqueue(input)
        startDrainIfNeeded()
    }

    func sendChord(_ scanCodes: [UInt32]) {
        for scanCode in scanCodes { submit(.keyDown(scanCode: scanCode)) }
        for scanCode in scanCodes.reversed() { submit(.keyUp(scanCode: scanCode)) }
    }

    func releaseAll() {
        guard !stopped else { return }
        let buttons = pressedButtons
        let scanCodes = pressedScanCodes.sorted()
        for button in buttons { submit(.mouseRelease(button)) }
        for scanCode in scanCodes { submit(.keyUp(scanCode: scanCode)) }
    }

    func shutdown() async {
        guard !stopped else { return }
        releaseAll()
        await waitUntilIdle()
        stop()
    }

    func stop() {
        stopped = true
        drainTask?.cancel()
        drainTask = nil
        pending.removeAll(keepingCapacity: false)
        pressedScanCodes.removeAll(keepingCapacity: false)
        pressedButtons.removeAll(keepingCapacity: false)
    }

    func waitUntilIdle() async {
        await drainTask?.value
    }

    private func enqueue(_ input: SpiceClientInput) {
        guard let last = pending.last else {
            pending.append(input)
            return
        }
        switch (last, input) {
        case let (.mouseMotion(oldX, oldY), .mouseMotion(newX, newY)):
            pending[pending.count - 1] = .mouseMotion(
                dx: saturatingAdd(oldX, newX),
                dy: saturatingAdd(oldY, newY)
            )
        case (.mousePosition, .mousePosition):
            pending[pending.count - 1] = input
        default:
            pending.append(input)
        }
    }

    private func startDrainIfNeeded() {
        guard drainTask == nil else { return }
        drainTask = Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        while !pending.isEmpty, !Task.isCancelled {
            let input = pending.removeFirst()
            do {
                try await send(input)
            } catch let error as SpiceError {
                stop()
                onFailure(error)
                return
            } catch {
                stop()
                onFailure(.protocolError(String(describing: error)))
                return
            }
        }
        drainTask = nil
        if !pending.isEmpty { startDrainIfNeeded() }
    }

    private func updatePressedState(for input: SpiceClientInput) {
        switch input {
        case let .keyDown(scanCode):
            pressedScanCodes.insert(scanCode)
        case let .keyUp(scanCode):
            pressedScanCodes.remove(scanCode)
        case let .mousePress(button):
            if !pressedButtons.contains(button) { pressedButtons.append(button) }
        case let .mouseRelease(button):
            pressedButtons.removeAll { $0 == button }
        case .lockModifiers, .mouseMotion, .mousePosition:
            break
        }
    }

    private func saturatingAdd(_ lhs: Int32, _ rhs: Int32) -> Int32 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard overflow else { return value }
        return rhs >= 0 ? .max : .min
    }
}
