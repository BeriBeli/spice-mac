// SPDX-License-Identifier: MIT
import Foundation

/// App preferences, backed by `UserDefaults`.
enum Preferences {
    private static let shareClipboardKey = "ShareClipboard"

    /// Whether to share the clipboard with the guest (both directions). Default
    /// ON (matches virt-viewer and the working behavior). Disable it when
    /// connecting to an untrusted VM — while on, anything you copy on the Mac is
    /// sent to the guest. Changes apply immediately to active connections.
    static var shareClipboard: Bool {
        get { (UserDefaults.standard.object(forKey: shareClipboardKey) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: shareClipboardKey) }
    }

    private static let trashAfterUseKey = "TrashConnectionFileAfterUse"

    /// Whether to move a `.vv` connection file to the Trash after using it to
    /// connect. Proxmox SPICE tickets are single-use and the file also carries the
    /// cluster CA, so keeping it around is pointless and a mild secret-hygiene risk.
    /// Default ON. It goes to the Trash (recoverable), not a permanent delete.
    static var trashConnectionFileAfterUse: Bool {
        get { (UserDefaults.standard.object(forKey: trashAfterUseKey) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: trashAfterUseKey) }
    }
}
