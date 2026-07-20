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
    /// Whether a `flagsChanged` event names a real modifier/lock key. Some
    /// CGEvent injectors emit an extra `flagsChanged` with an ordinary key code
    /// and an incomplete flags mask. The router must drop that event entirely:
    /// reconciling from its partial mask can release a real Shift/Control that is
    /// still part of the injected chord.
    public static func handlesFlagsChanged(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case MacVirtualKey.command, MacVirtualKey.rightCommand,
             MacVirtualKey.shift, MacVirtualKey.rightShift,
             MacVirtualKey.control, MacVirtualKey.rightControl,
             MacVirtualKey.option, MacVirtualKey.rightOption,
             MacVirtualKey.function, MacVirtualKey.capsLock:
            return true
        default:
            return false
        }
    }

    /// AppKit delivers Caps Lock through `flagsChanged`, but synthetic input can
    /// also produce `flagsChanged` for ordinary key codes. Only the actual lock
    /// key is an edge; treating every unknown code as a lock key injects a
    /// spurious keystroke (key code 0 becomes `A`).
    public static func lockKeyTransitions(forFlagsChanged keyCode: UInt16) -> [SpiceKeyTransition] {
        guard keyCode == MacVirtualKey.capsLock else { return [] }
        return [.press(keyCode), .release(keyCode)]
    }

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
