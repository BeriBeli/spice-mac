// SPDX-License-Identifier: MIT
import Combine
import Foundation
import SwiftSpice
import VVConfig

@MainActor
public final class SpiceClientDiagnosticsMonitor: ObservableObject {
    @Published public fileprivate(set) var snapshot: SpiceClientDiagnosticsSnapshot = .disabled

    public init() {}

    fileprivate func publish(_ snapshot: SpiceClientDiagnosticsSnapshot) {
        self.snapshot = snapshot
    }
}

/// Main-actor façade over the public SwiftSpice API used by Maspice.
@MainActor
public final class SpiceClient: ObservableObject {
    public enum Status: Equatable {
        case idle
        case connecting
        case connected
        case disconnected
        case failed(String)
    }

    @Published public private(set) var status: Status = .idle
    @Published public private(set) var frame: SpiceFrame?
    @Published public private(set) var frameSequence: UInt64 = 0
    @Published public private(set) var cursor: SpiceCursorState?
    @Published public private(set) var pointerMode: SpicePointerMode = .absolute
    @Published public private(set) var agentConnected = false
    @Published public private(set) var supportsDynamicResolution = false
    @Published public private(set) var isInputAvailable = false
    public let diagnosticsMonitor = SpiceClientDiagnosticsMonitor()

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
    public var presentationDiagnostics: SpicePresentationDiagnostics? {
        session?.presentationDiagnostics
    }

    private let parameters: SpiceConnectionParameters
    private var session: SpiceSession?
    private var agentManager: SpiceAgentManager?
    private var playbackSink: SpiceAudioPlaybackSink?
    private var inputPump: OrderedSpiceInputPump?
    private var connectionTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var supportTask: Task<Void, Never>?
    private var clipboardTask: Task<Void, Never>?
    private var displayConfigurationTask: Task<Void, Never>?
    private var latestAgentSupport: SpiceDisplayConfigurationSupport?
    private var latestClipboardState: SpiceClientClipboardDiagnosticsState = .unknown
    private let diagnosticsCollector = SpiceClientDiagnosticsCollector()
    private var diagnosticsTask: Task<Void, Never>?
    private var diagnosticsGeneration: UInt64 = 0
    private var generation: UInt64 = 0

    public init(parameters: SpiceConnectionParameters) {
        self.parameters = parameters
    }

    public func connect() {
        guard connectionTask == nil, session == nil else { return }
        generation &+= 1
        let currentGeneration = generation
        let session = SpiceSession()
        self.session = session
        status = .connecting
        frame = nil
        frameSequence = 0
        cursor = nil

        eventTask = Task { [weak self] in
            for await event in session.events {
                guard !Task.isCancelled else { return }
                self?.consume(event, generation: currentGeneration)
            }
        }
        connectionTask = Task { [weak self] in
            await self?.establish(session, generation: currentGeneration)
        }
    }

    public func disconnect() {
        setDiagnosticsEnabled(false)
        guard session != nil || connectionTask != nil else { return }
        generation &+= 1
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
        let oldSession = session
        let oldManager = agentManager
        let oldSink = playbackSink
        session = nil
        agentManager = nil
        playbackSink = nil
        resetRuntimeState(stoppingInput: false)
        status = .disconnected

        Task {
            if let oldInputPump { await oldInputPump.shutdown() }
            if let oldManager { await oldManager.stop() }
            if let oldSink { await oldSink.stop() }
            if let oldSession { await oldSession.disconnect() }
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
                guard self?.isCurrentDiagnosticsTask(taskGeneration) == true else {
                    return false
                }
                let sampledSession = self?.session
                let sampledAgentManager = self?.agentManager
                let sampleStartedAt = ContinuousClock().now
                async let sessionSnapshot = sampledSession?.diagnosticsSnapshot()
                async let agentSnapshot = sampledAgentManager?.diagnosticsSnapshot()
                let (sampledSessionDiagnostics, sampledAgentDiagnostics) = await (
                    sessionSnapshot,
                    agentSnapshot
                )
                guard self?.isCurrentDiagnosticsTask(taskGeneration) == true else {
                    return false
                }
                if let sampledSessionDiagnostics {
                    self?.diagnosticsCollector.recordSwiftSpiceDiagnostics(
                        sampledSessionDiagnostics,
                        sampledAt: sampleStartedAt
                    )
                }
                if let sampledAgentDiagnostics {
                    self?.diagnosticsCollector.recordAgentWireDiagnostics(
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

    private func establish(_ session: SpiceSession, generation: UInt64) async {
        do {
            let endpoint = try makeEndpoint()
            let info = try await session.connect(
                endpoint: endpoint,
                credentials: SpiceCredentials(password: parameters.password ?? "")
            )
            guard generation == self.generation, self.session === session else { return }

            pointerMode = SpicePointerMode(spiceMouseMode: info.currentMouseMode)
            isInputAvailable = info.channels.contains { $0.type == 3 && $0.id == 0 }
            if isInputAvailable {
                inputPump = OrderedSpiceInputPump(
                    session: session,
                    diagnostics: diagnosticsCollector
                ) { [weak self] error in
                    self?.fail(error.description, generation: generation)
                }
            }

            if info.channels.contains(where: { $0.type == 5 && $0.id == 0 }) {
                let sink = SpiceAudioPlaybackSink()
                playbackSink = sink
                do {
                    try await sink.start(session: session)
                } catch {
                    playbackSink = nil
                    NSLog("Maspice: audio playback unavailable: \(String(describing: error))")
                }
            }

            let manager = SpiceAgentManager(
                automaticallySynchronizesPasteboard: true,
                pasteboardSynchronizationEnabled: shareClipboard
            )
            agentManager = manager
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
            supportTask = Task { [weak self] in
                for await support in manager.displayConfigurationSupportEvents {
                    guard !Task.isCancelled else { return }
                    self?.consumeAgentSupport(support, generation: generation)
                }
            }
            clipboardTask = Task { [weak self] in
                for await event in manager.events {
                    guard !Task.isCancelled else { return }
                    self?.consumeClipboardEvent(event, generation: generation)
                }
            }
            displayConfigurationTask = Task { [weak self] in
                for await event in manager.displayConfigurationEvents {
                    guard !Task.isCancelled else { return }
                    self?.consumeDisplayConfigurationEvent(event, generation: generation)
                }
            }
            do {
                try await manager.start(session: session)
            } catch {
                diagnosticsCollector.recordAgentManagerStartFailure()
                NSLog("Maspice: guest-agent services unavailable: \(String(describing: error))")
            }

            guard generation == self.generation else { return }
            status = .connected
            connectionTask = nil
        } catch is CancellationError {
            return
        } catch let error as SpiceError {
            fail(error.description, generation: generation)
        } catch {
            fail(String(describing: error), generation: generation)
        }
    }

    private func consumeAgentSupport(
        _ support: SpiceDisplayConfigurationSupport,
        generation: UInt64
    ) {
        guard generation == self.generation else { return }
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

    private func consumeClipboardEvent(
        _ event: SpiceClipboardEvent,
        generation: UInt64
    ) {
        guard generation == self.generation else { return }
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

    private func consumeDisplayConfigurationEvent(
        _ event: SpiceDisplayConfigurationEvent,
        generation: UInt64
    ) {
        guard generation == self.generation else { return }
        diagnosticsCollector.recordDisplayConfigurationEvent(event)
    }

    private func consume(_ event: SpiceSessionEvent, generation: UInt64) {
        guard generation == self.generation else { return }
        switch event {
        case let .frame(frame):
            let sequence = frameSequence &+ 1
            diagnosticsCollector.recordClientFrameEvent(
                sequence: sequence
            )
            self.frame = frame
            frameSequence = sequence
        case let .surfaceDestroyed(surfaceID):
            if frame?.surfaceID == surfaceID { frame = nil }
        case let .cursor(cursor):
            self.cursor = cursor
        case let .mouseMode(_, current):
            pointerMode = SpicePointerMode(spiceMouseMode: current)
        case let .failed(error):
            fail(error.description, generation: generation)
        case .disconnected:
            setDiagnosticsEnabled(false)
            resetRuntimeState()
            status = .disconnected
        case .mouseMotionAcknowledged:
            diagnosticsCollector.recordMouseMotionAcknowledged()
        case .displayConfiguration, .keyboardModifiers, .migration:
            break
        }
    }

    public func recordDesktopViewUpdate(sequence: UInt64) {
        diagnosticsCollector.recordDesktopViewUpdate(sequence: sequence)
    }

    private func makeEndpoint() throws -> SpiceEndpoint {
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
            tlsPolicy: tlsPolicy
        )
    }

    private func fail(_ message: String, generation: UInt64) {
        guard generation == self.generation else { return }
        setDiagnosticsEnabled(false)
        connectionTask = nil
        resetRuntimeState()
        status = .failed(message)
    }

    private func resetRuntimeState(stoppingInput: Bool = true) {
        if stoppingInput { inputPump?.stop() }
        inputPump = nil
        frame = nil
        cursor = nil
        isInputAvailable = false
        agentConnected = false
        supportsDynamicResolution = false
        latestAgentSupport = nil
        latestClipboardState = shareClipboard ? .unknown : .disabled
    }
}
