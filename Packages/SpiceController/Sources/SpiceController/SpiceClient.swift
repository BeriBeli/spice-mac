// SPDX-License-Identifier: MIT
import Foundation
import Observation
import SwiftSpice
import VVConfig

struct SpiceVideoCodecFallbackPolicy {
    private(set) var didReconnect = false
    private var expectedDisconnectGeneration: UInt64?

    mutating func reset() {
        didReconnect = false
        expectedDisconnectGeneration = nil
    }

    mutating func shouldReconnect(
        after error: SpiceError,
        hasPresentedAdvancedVideo: Bool
    ) -> Bool {
        guard !didReconnect,
              !hasPresentedAdvancedVideo,
              case .videoCodecUnavailable = error
        else { return false }
        didReconnect = true
        return true
    }

    mutating func expectFailedAttemptDisconnect(generation: UInt64) {
        guard expectedDisconnectGeneration == nil else { return }
        expectedDisconnectGeneration = generation
    }

    mutating func cancelExpectedDisconnect() {
        expectedDisconnectGeneration = nil
    }

    mutating func consumeExpectedDisconnect(generation: UInt64) -> Bool {
        guard expectedDisconnectGeneration == generation else { return false }
        expectedDisconnectGeneration = nil
        return true
    }
}

@MainActor
@Observable
public final class SpiceClientDiagnosticsMonitor {
    public fileprivate(set) var snapshot: SpiceClientDiagnosticsSnapshot = .disabled

    public init() {}

    fileprivate func publish(_ snapshot: SpiceClientDiagnosticsSnapshot) {
        self.snapshot = snapshot
    }
}

/// Main-actor façade over the public SwiftSpice API used by Maspice.
@MainActor
@Observable
public final class SpiceClient {
    public enum Status: Equatable {
        case idle
        case connecting
        case connected
        case disconnected
        case failed(String)
    }

    public private(set) var status: Status = .idle
    public private(set) var agentConnected = false
    public private(set) var supportsDynamicResolution = false
    public private(set) var isInputAvailable = false
    public let diagnosticsMonitor = SpiceClientDiagnosticsMonitor()
    @ObservationIgnored public let desktop: SpiceDesktopSource

    public var shareClipboard = true {
        didSet {
            guard oldValue != shareClipboard else { return }
            let enabled = shareClipboard
            latestClipboardState = enabled
                ? agentConnected ? .waitingForCapabilities : .unavailable
                : .disabled
            diagnosticsCollector.seedAgentState(
                support: latestAgentSupport,
                clipboardState: latestClipboardState
            )
            guard let agentManager else { return }
            Task { await agentManager.setPasteboardSynchronizationEnabled(enabled) }
        }
    }

    public var title: String? { parameters.title }
    public var prefersFullscreen: Bool { parameters.fullscreen }

    @ObservationIgnored private let parameters: SpiceConnectionParameters
    @ObservationIgnored private let session: SpiceSession
    @ObservationIgnored private var agentManager: SpiceAgentManager?
    @ObservationIgnored private var playbackSink: SpiceAudioPlaybackSink?
    @ObservationIgnored private var inputPump: OrderedSpiceInputPump?
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var supportTask: Task<Void, Never>?
    @ObservationIgnored private var clipboardTask: Task<Void, Never>?
    @ObservationIgnored private var displayConfigurationTask: Task<Void, Never>?
    @ObservationIgnored private var latestAgentSupport: SpiceDisplayConfigurationSupport?
    @ObservationIgnored private var latestClipboardState: SpiceClientClipboardDiagnosticsState = .unknown
    @ObservationIgnored private let diagnosticsCollector = SpiceClientDiagnosticsCollector()
    @ObservationIgnored private var diagnosticsTask: Task<Void, Never>?
    @ObservationIgnored private var diagnosticsGeneration: UInt64 = 0
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var diagnosticsReadyGeneration: UInt64?
    @ObservationIgnored private var codecFallbackPolicy = SpiceVideoCodecFallbackPolicy()

    public init(parameters: SpiceConnectionParameters) {
        let session = SpiceSession()
        self.parameters = parameters
        self.session = session
        desktop = session.desktop
    }

    public func connect() {
        guard Self.canStartConnection(
            status: status,
            hasConnectionTask: connectionTask != nil
        ) else { return }
        generation &+= 1
        let currentGeneration = generation
        diagnosticsReadyGeneration = nil
        codecFallbackPolicy.reset()
        status = .connecting
        let session = self.session

        eventTask = Task { [weak self] in
            for await event in session.events {
                guard !Task.isCancelled else { return }
                await self?.consume(event)
            }
        }
        connectionTask = Task { [weak self] in
            await self?.establish(
                session,
                generation: currentGeneration,
                videoCodecPolicy: .h264AndMJPEG
            )
        }
    }

    public func disconnect() {
        setDiagnosticsEnabled(false)
        guard status != .idle || connectionTask != nil else { return }
        generation &+= 1
        codecFallbackPolicy.cancelExpectedDisconnect()
        diagnosticsReadyGeneration = nil
        connectionTask?.cancel()
        connectionTask = nil
        eventTask?.cancel()
        eventTask = nil
        supportTask?.cancel()
        supportTask = nil
        clipboardTask?.cancel()
        clipboardTask = nil
        displayConfigurationTask?.cancel()
        displayConfigurationTask = nil

        let oldInputPump = inputPump
        inputPump = nil
        let oldManager = agentManager
        let oldSink = playbackSink
        agentManager = nil
        playbackSink = nil
        resetRuntimeState(stoppingInput: false)
        status = .disconnected

        Task {
            if let oldInputPump { await oldInputPump.shutdown() }
            if let oldManager { await oldManager.stop() }
            if let oldSink { await oldSink.stop() }
            await session.disconnect()
        }
    }

    public func submit(_ input: SpiceClientInput) {
        inputPump?.submit(input)
    }

    public func sendCtrlAltDelete() {
        inputPump?.sendChord([0x1d, 0x38, 0x153])
    }

    public func releaseAllInput() {
        inputPump?.releaseAll()
    }

    public func setDiagnosticsEnabled(_ enabled: Bool) {
        guard diagnosticsCollector.isEnabled != enabled else { return }
        diagnosticsGeneration &+= 1
        diagnosticsTask?.cancel()
        diagnosticsTask = nil
        if enabled { diagnosticsCollector.reset() }
        diagnosticsCollector.setEnabled(enabled)
        if enabled {
            if codecFallbackPolicy.didReconnect {
                diagnosticsCollector.recordVideoCodecFallbackReconnect()
            }
            diagnosticsCollector.seedAgentState(
                support: latestAgentSupport,
                clipboardState: latestClipboardState
            )
        }
        diagnosticsMonitor.publish(diagnosticsCollector.snapshot())
        guard enabled else { return }

        let taskGeneration = diagnosticsGeneration
        diagnosticsTask = Task { @MainActor [weak self] in
            guard self?.isCurrentDiagnosticsTask(taskGeneration) == true else { return }

            let clock = ContinuousClock()
            let heartbeatInterval = Duration.milliseconds(100)
            let sampleUpstreamDiagnostics: @MainActor () async -> Bool = { [weak self] in
                guard let self,
                      self.isCurrentDiagnosticsTask(taskGeneration)
                else {
                    return false
                }
                let sampledSession = self.session
                let sampledAgentManager = self.agentManager
                let sampledConnectionGeneration = self.generation
                guard Self.canRecordUpstreamDiagnostics(
                    sampledGeneration: sampledConnectionGeneration,
                    currentGeneration: self.generation,
                    readyGeneration: self.diagnosticsReadyGeneration
                ) else {
                    return true
                }
                let sampleStartedAt = ContinuousClock().now
                async let sessionSnapshot = sampledSession.diagnosticsSnapshot()
                async let agentSnapshot = sampledAgentManager?.diagnosticsSnapshot()
                let (sampledSessionDiagnostics, sampledAgentDiagnostics) = await (
                    sessionSnapshot,
                    agentSnapshot
                )
                guard self.isCurrentDiagnosticsTask(taskGeneration) else {
                    return false
                }
                guard Self.canRecordUpstreamDiagnostics(
                    sampledGeneration: sampledConnectionGeneration,
                    currentGeneration: self.generation,
                    readyGeneration: self.diagnosticsReadyGeneration
                ) else {
                    // A reconnect started while the upstream actors were being
                    // sampled, or its reset has not completed. Drop the old
                    // epoch without stopping monitoring.
                    return true
                }
                self.diagnosticsCollector.recordSwiftSpiceDiagnostics(
                    sampledSessionDiagnostics,
                    sampledAt: sampleStartedAt
                )
                if let sampledAgentDiagnostics {
                    self.diagnosticsCollector.recordAgentWireDiagnostics(
                        sampledAgentDiagnostics
                    )
                }
                return true
            }

            guard await sampleUpstreamDiagnostics(),
            self?.isCurrentDiagnosticsTask(taskGeneration) == true else { return }

            var deadline = clock.now.advanced(by: heartbeatInterval)
            var ticksUntilPublication = 10

            while !Task.isCancelled {
                do {
                    try await clock.sleep(until: deadline)
                } catch {
                    return
                }
                let now = clock.now
                guard self?.isCurrentDiagnosticsTask(taskGeneration) == true else { return }

                let schedulingDelay = deadline.duration(to: now)
                if schedulingDelay > .zero {
                    self?.diagnosticsCollector.recordMainActorSchedulingDelay(schedulingDelay)
                }
                ticksUntilPublication -= 1
                if ticksUntilPublication == 0 {
                    guard await sampleUpstreamDiagnostics(),
                    self?.isCurrentDiagnosticsTask(taskGeneration) == true else { return }
                    if let snapshot = self?.diagnosticsCollector.snapshot() {
                        self?.diagnosticsMonitor.publish(snapshot)
                    }
                    ticksUntilPublication = 10
                }
                deadline = clock.now.advanced(by: heartbeatInterval)
            }
        }
    }

    private func isCurrentDiagnosticsTask(_ generation: UInt64) -> Bool {
        !Task.isCancelled
            && generation == diagnosticsGeneration
            && diagnosticsCollector.isEnabled
    }

    public func requestResolution(width: Int, height: Int) {
        let isBlocked = !supportsDynamicResolution || agentManager == nil
        diagnosticsCollector.recordMonitorConfigurationRequest(blocked: isBlocked)
        guard !isBlocked, let agentManager else { return }
        Task {
            do {
                try await agentManager.requestResolution(width: width, height: height)
            } catch {
                NSLog("Maspice: resolution request failed: \(String(describing: error))")
            }
        }
    }

    private func establish(
        _ session: SpiceSession,
        generation: UInt64,
        videoCodecPolicy: SpiceVideoCodecPolicy
    ) async {
        do {
            let endpoint = try makeEndpoint(videoCodecPolicy: videoCodecPolicy)
            let info = try await session.connect(
                endpoint: endpoint,
                credentials: SpiceCredentials(password: parameters.password ?? "")
            )
            guard generation == self.generation else { return }
            diagnosticsCollector.beginSwiftSpiceDiagnosticsEpoch()
            diagnosticsReadyGeneration = generation
            diagnosticsMonitor.publish(diagnosticsCollector.snapshot())

            isInputAvailable = info.channels.contains { $0.type == 3 && $0.id == 0 }
            if isInputAvailable {
                inputPump = OrderedSpiceInputPump(
                    session: session,
                    diagnostics: diagnosticsCollector
                ) { [weak self] error in
                    self?.fail(error.description, generation: generation)
                }
            }

            if playbackSink == nil,
               info.channels.contains(where: { $0.type == 5 && $0.id == 0 }) {
                let sink = SpiceAudioPlaybackSink()
                playbackSink = sink
                do {
                    try await sink.start(session: session)
                } catch {
                    playbackSink = nil
                    NSLog("Maspice: audio playback unavailable: \(String(describing: error))")
                }
            }

            guard generation == self.generation else { return }
            let manager: SpiceAgentManager
            if let agentManager {
                manager = agentManager
            } else {
                manager = SpiceAgentManager(
                    automaticallySynchronizesPasteboard: true,
                    pasteboardSynchronizationEnabled: shareClipboard
                )
                agentManager = manager
                supportTask = Task { [weak self] in
                    for await support in manager.displayConfigurationSupportEvents {
                        guard !Task.isCancelled else { return }
                        guard let self, self.agentManager === manager else { return }
                        self.consumeAgentSupport(support)
                    }
                }
                clipboardTask = Task { [weak self] in
                    for await event in manager.events {
                        guard !Task.isCancelled else { return }
                        guard let self, self.agentManager === manager else { return }
                        self.consumeClipboardEvent(event)
                    }
                }
                displayConfigurationTask = Task { [weak self] in
                    for await event in manager.displayConfigurationEvents {
                        guard !Task.isCancelled else { return }
                        guard let self, self.agentManager === manager else { return }
                        self.consumeDisplayConfigurationEvent(event)
                    }
                }
                do {
                    try await manager.start(session: session)
                } catch {
                    diagnosticsCollector.recordAgentManagerStartFailure()
                    NSLog("Maspice: guest-agent services unavailable: \(String(describing: error))")
                }
            }
            guard generation == self.generation else { return }
            agentConnected = info.agentConnected
            let initialSupport = SpiceDisplayConfigurationSupport(
                agentConnected: info.agentConnected,
                hasExplicitPeerCapabilities: false,
                supportsMonitorConfiguration: info.agentConnected,
                supportsSparseMonitors: false,
                supportsMonitorPositions: false
            )
            latestAgentSupport = initialSupport
            latestClipboardState = shareClipboard
                ? info.agentConnected ? .waitingForCapabilities : .unavailable
                : .disabled
            diagnosticsCollector.seedAgentState(
                support: initialSupport,
                clipboardState: latestClipboardState
            )
            completeEstablishment(generation: generation)
        } catch is CancellationError {
            return
        } catch let error as SpiceError {
            await handleSessionFailure(error, generation: generation)
        } catch {
            fail(String(describing: error), generation: generation)
        }
    }

    private func consumeAgentSupport(_ support: SpiceDisplayConfigurationSupport) {
        latestAgentSupport = support
        agentConnected = support.agentConnected
        supportsDynamicResolution = support.agentConnected
            && support.supportsMonitorConfiguration
        if !support.agentConnected, latestClipboardState != .disabled {
            latestClipboardState = .unavailable
        } else if support.agentConnected, latestClipboardState == .unknown {
            latestClipboardState = .waitingForCapabilities
        }
        diagnosticsCollector.recordAgentSupport(support)
    }

    private func consumeClipboardEvent(_ event: SpiceClipboardEvent) {
        switch event {
        case .ready:
            latestClipboardState = .ready
        case .unavailable:
            latestClipboardState = .unavailable
        case .failed:
            latestClipboardState = .failed
        case .guestText, .localTextOffered, .oversizedLocalText:
            break
        }
        diagnosticsCollector.recordClipboardEvent(event)
    }

    private func consumeDisplayConfigurationEvent(_ event: SpiceDisplayConfigurationEvent) {
        diagnosticsCollector.recordDisplayConfigurationEvent(event)
    }

    private func consume(_ event: SpiceSessionEvent) async {
        let eventGeneration = generation
        switch event {
        case let .failed(error):
            await handleSessionFailure(error, generation: eventGeneration)
        case .disconnected:
            // The fallback sequence explicitly disconnects before reconnecting,
            // so this old-lifecycle event is guaranteed to be queued before
            // any event from the replacement connection. Ignore it instead of
            // closing the session window while the MJPEG retry is pending.
            guard !codecFallbackPolicy.consumeExpectedDisconnect(
                generation: eventGeneration
            ) else { return }
            diagnosticsReadyGeneration = nil
            setDiagnosticsEnabled(false)
            resetRuntimeState()
            status = .disconnected
        case .mouseMotionAcknowledged:
            diagnosticsCollector.recordMouseMotionAcknowledged()
        case .displayConfiguration, .keyboardModifiers, .migration:
            break
        }
    }

    private func handleSessionFailure(_ error: SpiceError, generation: UInt64) async {
        guard generation == self.generation else { return }
        guard case .videoCodecUnavailable = error else {
            fail(error.description, generation: generation)
            return
        }

        let diagnostics = await session.diagnosticsSnapshot()
        guard generation == self.generation else { return }
        let hasPresentedAdvancedVideo = diagnostics.advancedVideoPresentedFrames > 0
        if codecFallbackPolicy.shouldReconnect(
            after: error,
            hasPresentedAdvancedVideo: hasPresentedAdvancedVideo
        ) {
            NSLog("Maspice: hardware video unavailable; reconnecting once with MJPEG")
            reconnectUsingMJPEG(generation: generation)
        } else {
            fail(error.description, generation: generation)
        }
    }

    private func reconnectUsingMJPEG(generation failedGeneration: UInt64) {
        guard failedGeneration == generation,
              codecFallbackPolicy.didReconnect
        else { return }
        diagnosticsCollector.recordVideoCodecFallbackReconnect()
        generation &+= 1
        let retryGeneration = generation
        codecFallbackPolicy.expectFailedAttemptDisconnect(
            generation: retryGeneration
        )
        diagnosticsReadyGeneration = nil
        diagnosticsCollector.beginSwiftSpiceDiagnosticsEpoch()
        diagnosticsMonitor.publish(diagnosticsCollector.snapshot())

        connectionTask?.cancel()
        connectionTask = nil

        let oldInputPump = inputPump
        resetRuntimeState(stoppingInput: false)
        status = .connecting
        let retrySession = session

        connectionTask = Task { [weak self] in
            if let oldInputPump { await oldInputPump.shutdown() }
            // SpiceSession failures publish `.failed` rather than a trailing
            // `.disconnected`. Make teardown explicit so the event suppressed
            // above is guaranteed to exist and precede the replacement
            // lifecycle in the session mailbox.
            await retrySession.disconnect()
            if let manager = self?.agentManager {
                await manager.waitForSessionReconnectBoundary()
            }
            guard let self, retryGeneration == self.generation else { return }
            await self.establish(
                retrySession,
                generation: retryGeneration,
                videoCodecPolicy: .mjpegOnly
            )
        }
    }

    private func makeEndpoint(
        videoCodecPolicy: SpiceVideoCodecPolicy
    ) throws -> SpiceEndpoint {
        let selectedPort = parameters.tlsPort ?? parameters.port
        guard let selectedPort, let port = UInt16(exactly: selectedPort) else {
            throw SpiceError.connectionFailed("connection file has no valid port")
        }
        let tlsPolicy: TLSTrustPolicy?
        if parameters.tlsPort == nil {
            tlsPolicy = nil
        } else if let ca = parameters.caCertificate, ca.isEmpty == false {
            if let subject = parameters.certificateSubject, subject.isEmpty == false {
                tlsPolicy = .virtViewerCertificateAuthority(
                    certificates: [Data(ca.utf8)],
                    expectedSubject: subject
                )
            } else {
                tlsPolicy = .customCertificateAuthority(
                    certificates: [Data(ca.utf8)]
                )
            }
        } else {
            tlsPolicy = .system
        }
        return SpiceEndpoint(
            host: parameters.host,
            port: port,
            tlsPolicy: tlsPolicy,
            videoCodecPolicy: videoCodecPolicy
        )
    }

    private func completeEstablishment(generation: UInt64) {
        guard generation == self.generation else { return }
        status = .connected
        connectionTask = nil
    }

    package func completeEstablishmentForTesting(generation: UInt64) {
        completeEstablishment(generation: generation)
    }

    package func fail(_ message: String, generation: UInt64) {
        guard generation == self.generation else { return }
        // Establishment remains suspended while audio and Agent services
        // start. Advance the epoch before cancelling it so none of those old
        // continuations can publish `.connected` after this terminal failure.
        self.generation &+= 1
        codecFallbackPolicy.cancelExpectedDisconnect()
        diagnosticsReadyGeneration = nil
        setDiagnosticsEnabled(false)
        connectionTask?.cancel()
        connectionTask = nil
        eventTask?.cancel()
        eventTask = nil
        supportTask?.cancel()
        supportTask = nil
        clipboardTask?.cancel()
        clipboardTask = nil
        displayConfigurationTask?.cancel()
        displayConfigurationTask = nil

        let oldInputPump = inputPump
        let oldManager = agentManager
        let oldSink = playbackSink
        inputPump = nil
        agentManager = nil
        playbackSink = nil
        resetRuntimeState(stoppingInput: false)
        status = .failed(message)

        let session = self.session
        Task {
            if let oldInputPump { await oldInputPump.shutdown() }
            if let oldManager { await oldManager.stop() }
            if let oldSink { await oldSink.stop() }
            await session.disconnect()
        }
    }

    private func resetRuntimeState(stoppingInput: Bool = true) {
        if stoppingInput { inputPump?.stop() }
        inputPump = nil
        isInputAvailable = false
        agentConnected = false
        supportsDynamicResolution = false
        latestAgentSupport = nil
        latestClipboardState = shareClipboard ? .unknown : .disabled
    }

    static func canStartConnection(
        status: Status,
        hasConnectionTask: Bool
    ) -> Bool {
        status == .idle && !hasConnectionTask
    }

    static func canRecordUpstreamDiagnostics(
        sampledGeneration: UInt64,
        currentGeneration: UInt64,
        readyGeneration: UInt64?
    ) -> Bool {
        sampledGeneration == currentGeneration
            && readyGeneration == sampledGeneration
    }
}
