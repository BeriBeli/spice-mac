import Foundation
import Testing
import WebKit
@testable import Maspice

@MainActor struct PortalNavigationRecoveryTests {
    @Test func repeatedFailuresRearmObservationAndSuccessfulNavigationClearsRecovery() async throws {
        // WebKit blocks this restricted port locally, so no external host is used.
        let model = RavadaPortalModel(initialURL: URL(string: "https://127.0.0.1:1/")!,
                                      dataStore: .nonPersistent(), onConnectionFile: { _ in }, onError: { _ in })
        var observer = Task { await model.observeNavigations() }
        defer { observer.cancel(); model.page.stopLoading(); model.cancelPendingWork() }
        try await waitUntil("initial failure") { model.loadFailure != nil }
        let firstRevision = model.observationID
        #expect(firstRevision > 0)
        await observer.value

        observer = Task { await model.observeNavigations() }
        await Task.yield()
        model.reloadOrStop()
        #expect(model.loadFailure == nil)
        try await waitUntil("toolbar reload failure") { model.loadFailure != nil }
        #expect(model.observationID > firstRevision)
        await observer.value

        observer = Task { await model.observeNavigations() }
        await Task.yield()
        model.page.load(simulatedRequest: URLRequest(url: URL(string: "https://fixture.example/")!),
                        responseHTML: "<title>Recovered</title><p>Portal is available.</p>")
        try await waitUntil("successful navigation") { model.page.title == "Recovered" && !model.page.isLoading }
        #expect(model.loadFailure == nil)
    }

    private func waitUntil(_ phase: String, _ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Portal did not reach the expected recovery state within five seconds: \(phase).")
        throw CancellationError()
    }
}
