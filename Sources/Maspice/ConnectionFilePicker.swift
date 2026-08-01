// SPDX-License-Identifier: MIT
import AppKit

/// The smallest AppKit bridge for a modal open panel. Window and session
/// ownership remain in SwiftUI.
@MainActor
enum ConnectionFilePicker {
    static func chooseFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = VVDocument.contentTypes
        panel.prompt = "Open"
        panel.message = "Open a direct SPICE connection file (.vv)"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
