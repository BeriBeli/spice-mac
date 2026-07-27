// SPDX-License-Identifier: MIT
import Observation

/// SwiftUI-owned application state shared across launcher and session scenes.
@MainActor
@Observable
final class ApplicationModel {
    private var sessionFailures: [String] = []

    var sessionFailureMessage: String? {
        sessionFailures.first
    }

    func presentSessionFailure(_ message: String) {
        sessionFailures.append(message)
    }

    func clearSessionFailure() {
        if !sessionFailures.isEmpty {
            sessionFailures.removeFirst()
        }
    }
}
