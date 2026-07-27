// SPDX-License-Identifier: MIT
import Foundation

/// Hashable scene value used by `WindowGroup(for:)` to create an independent
/// window for each short-lived SPICE connection file.
struct SessionRequest: Codable, Hashable, Identifiable {
    let id: UUID
    let url: URL
    let removesFileAfterStart: Bool

    init(id: UUID = UUID(), url: URL, removesFileAfterStart: Bool = false) {
        self.id = id
        self.url = url
        self.removesFileAfterStart = removesFileAfterStart
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case url
        case removesFileAfterStart
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        removesFileAfterStart = try container.decodeIfPresent(
            Bool.self,
            forKey: .removesFileAfterStart) ?? false
    }
}
