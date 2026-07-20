// SPDX-License-Identifier: MIT
import Foundation

/// One physical key transition emitted on the SPICE inputs channel.
public enum SpiceKeyTransition: Equatable {
    case press(UInt16)
    case release(UInt16)
}

/// Pure routing policy shared by the AppKit input router and its dependency-free
/// regression tests. Accessibility/CGEvent injection may put modifiers only on
/// the key event, without sending the `flagsChanged` events used by hardware.
/// These helpers turn that one synthetic event into a balanced guest chord.
public enum SpiceKeyboardRouting {
    /// Hardware events report source PID 0. Accessibility/CGEvent injectors
    /// report their process PID. Missing/invalid source metadata stays on the
    /// physical path so the fallback cannot broaden accidentally.
    public static func usesSyntheticModifierChord(sourcePID: Int64?) -> Bool {
        guard let sourcePID else { return false }
        return sourcePID > 0
    }

    public static func syntheticKeyDownTransitions(
        keyCode: UInt16,
        requestedModifiers: [UInt16],
        heldModifiers: Set<UInt16> = []
    ) -> (transitions: [SpiceKeyTransition], ownedModifiers: [UInt16]) {
        let owned = requestedModifiers.filter { !heldModifiers.contains($0) }
        return (owned.map(SpiceKeyTransition.press) + [.press(keyCode)], owned)
    }

    public static func syntheticKeyUpTransitions(
        keyCode: UInt16,
        ownedModifiers: [UInt16]
    ) -> [SpiceKeyTransition] {
        [.release(keyCode)] + ownedModifiers.reversed().map(SpiceKeyTransition.release)
    }
}
