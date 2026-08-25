// SPDX-License-Identifier: MIT
import Dispatch
import SwiftSpice

/// Serializes AppKit-produced input before it crosses the SwiftSpice actor boundary.
/// Key/button edges are lossless; adjacent pointer updates are coalesced.
@MainActor
final class OrderedSpiceInputPump {
    private typealias MeasurementToken = SpiceClientDiagnosticsCollector.MeasurementToken

    private struct PendingInput {
        var input: SpiceClientInput
        var measurementToken: MeasurementToken?
        var enqueuedAt: ContinuousClock.Instant?
    }

    private let send: @Sendable (SpiceClientInput) async throws -> Void
    private let sendExecutor = DispatchQueue(
        label: "io.github.beribeli.Maspice.input-send",
        qos: .userInteractive,
        autoreleaseFrequency: .workItem
    )
    private let onFailure: @MainActor (SpiceError) -> Void
    private let diagnostics: SpiceClientDiagnosticsCollector?
    private var pending: [PendingInput] = []
    private var pendingCountByMeasurement: [MeasurementToken: Int] = [:]
    private var drainTask: Task<Void, Never>?
    private var pressedScanCodes: Set<UInt32> = []
    private var pressedButtons: [SpiceMouseButton] = []
    private var stopped = false

    init(
        session: SpiceSession,
        diagnostics: SpiceClientDiagnosticsCollector? = nil,
        onFailure: @escaping @MainActor (SpiceError) -> Void
    ) {
        self.send = { input in try await session.send(input) }
        self.diagnostics = diagnostics
        self.onFailure = onFailure
    }

    init(
        send: @escaping @Sendable (SpiceClientInput) async throws -> Void,
        diagnostics: SpiceClientDiagnosticsCollector? = nil,
        onFailure: @escaping @MainActor (SpiceError) -> Void
    ) {
        self.send = send
        self.diagnostics = diagnostics
        self.onFailure = onFailure
    }

    func submit(_ input: SpiceClientInput) {
        guard !stopped else { return }
        updatePressedState(for: input)
        let measurementToken: MeasurementToken? = diagnostics?.recordInputSubmitted(
            isMotion: isMotion(input)
        )
        if enqueue(input, measurementToken: measurementToken) {
            diagnostics?.recordInputCoalesced(token: measurementToken)
        }
        diagnostics?.recordPendingInputCount(
            measurementToken.flatMap { pendingCountByMeasurement[$0] } ?? 0,
            token: measurementToken
        )
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
        pendingCountByMeasurement.removeAll(keepingCapacity: false)
        let measurementToken = diagnostics?.currentMeasurementToken
        diagnostics?.recordPendingInputCount(0, token: measurementToken)
        pressedScanCodes.removeAll(keepingCapacity: false)
        pressedButtons.removeAll(keepingCapacity: false)
    }

    func waitUntilIdle() async {
        while let drainTask {
            await drainTask.value
        }
    }

    @discardableResult
    private func enqueue(
        _ input: SpiceClientInput,
        measurementToken: MeasurementToken?
    ) -> Bool {
        let item = PendingInput(
            input: input,
            measurementToken: measurementToken,
            enqueuedAt: measurementToken == nil ? nil : ContinuousClock().now
        )
        guard let last = pending.last else {
            pending.append(item)
            adjustPendingCount(for: item.measurementToken, by: 1)
            return false
        }
        switch (last.input, input) {
        case let (.mouseMotion(oldX, oldY), .mouseMotion(newX, newY)):
            pending[pending.count - 1].input = .mouseMotion(
                dx: saturatingAdd(oldX, newX),
                dy: saturatingAdd(oldY, newY)
            )
            if pending[pending.count - 1].measurementToken != item.measurementToken {
                adjustPendingCount(
                    for: pending[pending.count - 1].measurementToken,
                    by: -1
                )
                adjustPendingCount(for: item.measurementToken, by: 1)
                pending[pending.count - 1].measurementToken = item.measurementToken
                pending[pending.count - 1].enqueuedAt = item.enqueuedAt
            }
            return true
        case (.mousePosition, .mousePosition):
            pending[pending.count - 1].input = input
            if pending[pending.count - 1].measurementToken != item.measurementToken {
                adjustPendingCount(
                    for: pending[pending.count - 1].measurementToken,
                    by: -1
                )
                adjustPendingCount(for: item.measurementToken, by: 1)
                pending[pending.count - 1].measurementToken = item.measurementToken
                pending[pending.count - 1].enqueuedAt = item.enqueuedAt
            }
            return true
        default:
            pending.append(item)
            adjustPendingCount(for: item.measurementToken, by: 1)
            return false
        }
    }

    private func startDrainIfNeeded() {
        guard drainTask == nil, !pending.isEmpty else { return }
        if isMotion(pending[0].input) {
            // Give pointer samples from the same AppKit turn one coalescing
            // opportunity. Key and button edges bypass this yield entirely.
            drainTask = Task { [weak self] in
                await Task.yield()
                self?.beginSend()
            }
            return
        }
        beginSend()
    }

    private func beginSend() {
        guard !pending.isEmpty else {
            drainTask = nil
            return
        }
        let pendingInput = pending.removeFirst()
        let measurementToken = pendingInput.measurementToken
        adjustPendingCount(for: measurementToken, by: -1)
        diagnostics?.recordPendingInputCount(
            measurementToken.flatMap { pendingCountByMeasurement[$0] } ?? 0,
            token: measurementToken
        )
        let send = self.send
        drainTask = Task.detached(
            executorPreference: sendExecutor,
            priority: .high
        ) { [weak self] in
            let sendStartedAt = ContinuousClock().now
            let result: Result<Void, SpiceError>
            do {
                try await send(pendingInput.input)
                result = .success(())
            } catch let error as SpiceError {
                result = .failure(error)
            } catch {
                result = .failure(.protocolError(String(describing: error)))
            }
            await self?.finishSend(
                pendingInput,
                startedAt: sendStartedAt,
                completedAt: ContinuousClock().now,
                result: result
            )
        }
    }

    private func finishSend(
        _ pendingInput: PendingInput,
        startedAt: ContinuousClock.Instant,
        completedAt: ContinuousClock.Instant,
        result: Result<Void, SpiceError>
    ) {
        let measurementToken = pendingInput.measurementToken
        let measuresLatency = diagnostics?.isCurrentMeasurement(measurementToken) == true
        if measuresLatency, let enqueuedAt = pendingInput.enqueuedAt {
            diagnostics?.recordInputDequeued(
                queueWait: enqueuedAt.duration(to: startedAt),
                token: measurementToken
            )
        }
        switch result {
        case .success:
            if measuresLatency {
                diagnostics?.recordInputSent(
                    isMotion: isMotion(pendingInput.input),
                    sendDuration: startedAt.duration(to: completedAt),
                    token: measurementToken
                )
            }
        case let .failure(error):
            if measuresLatency {
                diagnostics?.recordSendFailure(
                    sendDuration: startedAt.duration(to: completedAt),
                    token: measurementToken
                )
            }
            stop()
            onFailure(error)
            return
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

    private func isMotion(_ input: SpiceClientInput) -> Bool {
        switch input {
        case .mouseMotion, .mousePosition:
            true
        case .keyDown, .keyUp, .lockModifiers, .mousePress, .mouseRelease:
            false
        }
    }

    private func adjustPendingCount(for token: MeasurementToken?, by delta: Int) {
        guard let token else { return }
        let updated = (pendingCountByMeasurement[token] ?? 0) + delta
        if updated > 0 {
            pendingCountByMeasurement[token] = updated
        } else {
            pendingCountByMeasurement.removeValue(forKey: token)
        }
    }
}
