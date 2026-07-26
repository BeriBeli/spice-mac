// SPDX-License-Identifier: MIT

/// One-shot session lifetime decisions kept independent of AppKit, SwiftUI, and
/// CocoaSpice so cleanup and disconnect navigation can be tested deterministically.
public struct SessionLifecycle: Equatable, Sendable {
    public private(set) var didStart = false
    public private(set) var isActive = false

    public init() {}

    /// Returns true exactly once, when the caller should connect the client.
    public mutating func start() -> Bool {
        guard !didStart else { return false }
        didStart = true
        isActive = true
        return true
    }

    /// Returns true when an active session needs explicit teardown.
    public mutating func stop() -> Bool {
        guard isActive else { return false }
        isActive = false
        return true
    }

    /// Returns true for a remote disconnect or connection failure from a still-
    /// active session. A terminal callback caused by an explicit `stop()` must
    /// not reopen the launcher after the user has closed the window.
    public mutating func connectionDidTerminate() -> Bool {
        stop()
    }
}

public struct SessionCommandAvailability: Equatable, Sendable {
    public let hasActiveSession: Bool
    public let hasInput: Bool

    public init(hasActiveSession: Bool, hasInput: Bool) {
        self.hasActiveSession = hasActiveSession
        self.hasInput = hasInput
    }

    public var canSendCtrlAltDelete: Bool { hasActiveSession && hasInput }
    public var canReleaseCursor: Bool { hasActiveSession && hasInput }
}
