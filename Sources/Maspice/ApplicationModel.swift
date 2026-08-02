// SPDX-License-Identifier: MIT
import Foundation
import Observation
import SpiceSessionLogic

/// SwiftUI-owned application state shared across launcher and session scenes.
@MainActor
@Observable
final class ApplicationModel {
    private var sessionFailures: [String] = []
    private var portalPresentationIsAuthorized = false
    private var portalPresentationIsActive = false
    private var authorizedSessionPresentations = Set<UUID>()
    private var activeSessionPresentations = Set<UUID>()

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

    func authorizePortalPresentation() {
        portalPresentationIsAuthorized = true
    }

    func activatePortalPresentation() -> Bool {
        if portalPresentationIsActive { return true }
        guard portalPresentationIsAuthorized else { return false }
        portalPresentationIsAuthorized = false
        portalPresentationIsActive = true
        return true
    }

    func deactivatePortalPresentation() {
        portalPresentationIsActive = false
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
