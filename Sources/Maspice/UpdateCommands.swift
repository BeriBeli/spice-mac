// SPDX-License-Identifier: MIT
import Combine
import Observation
import Sparkle
import SwiftUI

@MainActor
@Observable
private final class CheckForUpdatesViewModel {
    private(set) var canCheckForUpdates = false
    @ObservationIgnored private var cancellable: AnyCancellable?

    init(updater: SPUUpdater) {
        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheckForUpdates in
                MainActor.assumeIsolated {
                    self?.canCheckForUpdates = canCheckForUpdates
                }
            }
    }
}

struct CheckForUpdatesCommand: View {
    @State private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        _viewModel = State(initialValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}
