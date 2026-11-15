// SPDX-License-Identifier: MIT
import Foundation
import Sparkle
import Testing
@testable import Maspice

@MainActor
@Suite("Sparkle update channels")
struct UpdateChannelDelegateTests {
    @Test func stableIsTheDefaultAndBetaOptInPersists() throws {
        let suite = "MaspiceTests.Updates.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let delegate = UpdateChannelDelegate(defaults: defaults)
        // Never start this controller: no network checks, installer or UI.
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: delegate, userDriverDelegate: nil)
        let updater = controller.updater

        #expect(delegate.allowedChannels(for: updater).isEmpty)
        defaults.set(true, forKey: Preferences.receiveBetaUpdatesKey)
        #expect(delegate.allowedChannels(for: updater) == ["beta"])
        let relaunchedDelegate = UpdateChannelDelegate(defaults: defaults)
        #expect(relaunchedDelegate.allowedChannels(for: updater) == ["beta"])
        defaults.set(false, forKey: Preferences.receiveBetaUpdatesKey)
        #expect(relaunchedDelegate.allowedChannels(for: updater).isEmpty)
    }
}
