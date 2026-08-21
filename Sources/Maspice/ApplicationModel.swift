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

    @discardableResult
    func presentSessionDiagnostics(
        for id: UUID,
        title: String,
        client: SpiceClient
    ) -> SessionDiagnosticsRequest {
        if let presentation = sessionDiagnosticsPresentations[id] {
            return presentation.request
        }

        let request = SessionDiagnosticsRequest(
            sessionID: id,
            presentationID: UUID()
        )
        client.setDiagnosticsEnabled(true)
        sessionDiagnosticsPresentations[id] = SessionDiagnosticsPresentation(
            request: request,
            title: title,
            client: client
        )
        return request
    }

    func dismissSessionDiagnostics(_ request: SessionDiagnosticsRequest) {
        guard let presentation = sessionDiagnosticsPresentations[request.sessionID],
              presentation.request == request else {
            return
        }
        sessionDiagnosticsPresentations.removeValue(forKey: request.sessionID)
        presentation.client.setDiagnosticsEnabled(false)
        retainSessionDiagnosticsSummary(
            presentation.client.diagnosticsMonitor.snapshot.diagnosticsSummary
        )
    }

    func sessionDiagnosticsPresentation(
        for request: SessionDiagnosticsRequest
    ) -> SessionDiagnosticsPresentation? {
        guard let presentation = sessionDiagnosticsPresentations[request.sessionID],
              presentation.request == request else {
            return nil
        }
        return presentation
    }

    func sessionDiagnosticsRequest(for id: UUID) -> SessionDiagnosticsRequest? {
        sessionDiagnosticsPresentations[id]?.request
    }

    func isSessionDiagnosticsPresented(for id: UUID) -> Bool {
        sessionDiagnosticsPresentations[id] != nil
    }

    func copySessionDiagnosticsSummary(for request: SessionDiagnosticsRequest) {
        guard let presentation = sessionDiagnosticsPresentation(for: request) else {
            return
        }
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
    let request: SessionDiagnosticsRequest
    let title: String
    let client: SpiceClient
}
