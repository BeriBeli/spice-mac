import Foundation

/// Lightweight input-path tracing, enabled by setting the environment variable
/// `SPICEMAC_INPUT_DEBUG=1`. Logs go to stderr / the unified log via NSLog.
@inline(__always)
public func spiceInputLog(_ message: @autoclosure () -> String) {
    if InputDebug.enabled {
        NSLog("[SpiceInput] %@", message())
    }
}

/// Clipboard-path tracing, enabled by the same `SPICEMAC_INPUT_DEBUG=1`.
@inline(__always)
public func spiceClipboardLog(_ message: @autoclosure () -> String) {
    if InputDebug.enabled {
        NSLog("[SpiceClipboard] %@", message())
    }
}

enum InputDebug {
    static let enabled = ProcessInfo.processInfo.environment["SPICEMAC_INPUT_DEBUG"] != nil
}
