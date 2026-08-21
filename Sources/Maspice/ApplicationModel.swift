// SPDX-License-Identifier: MIT
import Foundation
import Observation
import SpiceController
import SpiceSessionLogic

/// SwiftUI-owned application state shared across launcher and session scenes.
enum MainDestination: Equatable {
    case launcher
    case portal
}

@MainActor
@Observable
final class ApplicationModel {
    private(set) var mainDestination: MainDestination = .launcher
    private var sessionFailures: [String] = []
    private(set) var lastSessionDiagnosticsSummary: String?
    private var authorizedSessionPresentations = Set<UUID>()
    private var activeSessionPresentations = Set<UUID>()
    private var sessionDiagnosticsPresentations: [UUID: SessionDiagnosticsPresentation] = [:]

    var sessionFailureMessage: String? {
        sessionFailures.first
    }

    func presentSessionFailure(_ message: String) {
        sessionFailures.append(SessionFailureMessage.detail(from: message))
    }

    func clearSessionFailure() {
        if !sessionFailures.isEmpty {
            sessionFailures.removeFirst()
        }
    }

    func retainSessionDiagnosticsSummary(_ summary: String) {
        lastSessionDiagnosticsSummary = summary
    }

    func presentSessionDiagnostics(
        for id: UUID,
        title: String,
        client: SpiceClient
    ) {
        client.setDiagnosticsEnabled(true)
        sessionDiagnosticsPresentations[id] = SessionDiagnosticsPresentation(
            title: title,
            client: client
        )
    }

    func dismissSessionDiagnostics(for id: UUID) {
        guard let presentation = sessionDiagnosticsPresentations.removeValue(forKey: id) else {
            return
        }
        presentation.client.setDiagnosticsEnabled(false)
        retainSessionDiagnosticsSummary(
            presentation.client.diagnosticsMonitor.snapshot.diagnosticsSummary
        )
    }

    func sessionDiagnosticsPresentation(
        for id: UUID
    ) -> SessionDiagnosticsPresentation? {
        sessionDiagnosticsPresentations[id]
    }

    func isSessionDiagnosticsPresented(for id: UUID) -> Bool {
        sessionDiagnosticsPresentations[id] != nil
    }

    func copySessionDiagnosticsSummary(for id: UUID) {
        guard let presentation = sessionDiagnosticsPresentations[id] else { return }
        SessionDiagnosticsClipboard.copy(
            presentation.client.diagnosticsMonitor.snapshot.diagnosticsSummary
        )
    }

    func showLauncher() {
        mainDestination = .launcher
    }

    func showPortal() {
        mainDestination = .portal
    }

    func authorizeSessionPresentation(_ request: SessionRequest) {
        authorizedSessionPresentations.insert(request.id)
    }

    func activateSessionPresentation(for id: UUID) -> Bool {
        if activeSessionPresentations.contains(id) { return true }
        guard authorizedSessionPresentations.remove(id) != nil else { return false }
        activeSessionPresentations.insert(id)
        return true
    }

    func isSessionPresentationActive(for id: UUID) -> Bool {
        activeSessionPresentations.contains(id)
    }

    func deactivateSessionPresentation(for id: UUID) {
        activeSessionPresentations.remove(id)
    }
}

struct SessionDiagnosticsPresentation {
    let title: String
    let client: SpiceClient
}
