// SPDX-License-Identifier: MIT
import Foundation
import Sparkle

/// Sparkle always includes the default (stable) channel. Beta is an explicit
/// opt-in, including for users who installed a beta archive manually.
final class UpdateChannelDelegate: NSObject, SPUUpdaterDelegate {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        defaults.bool(forKey: Preferences.receiveBetaUpdatesKey) ? ["beta"] : []
    }
}
