// SPDX-License-Identifier: MIT
import Foundation

/// Thread-safe generation gate for work that crosses from the SPICE worker to
/// AppKit's main queue. A disable/enable cycle invalidates every token captured
/// before the cycle, so delayed guest clipboard writes cannot become valid again.
public final class ClipboardSharingGate: @unchecked Sendable {
    public struct Token: Equatable, Sendable {
        fileprivate let generation: UInt64
    }

    private let lock = NSLock()
    private var enabled = false
    private var generation: UInt64 = 0

    public init() {}

    public func setEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        generation &+= 1
    }

    public func tokenIfEnabled() -> Token? {
        lock.lock()
        defer { lock.unlock() }
        return enabled ? Token(generation: generation) : nil
    }

    public func accepts(_ token: Token) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled && token.generation == generation
    }
}
