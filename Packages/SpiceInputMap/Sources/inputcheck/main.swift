// SPDX-License-Identifier: MIT
import Foundation
import SpiceInputMap

let t = TestRunner()
print("SpiceInputMap checks")

func code(_ k: UInt16) -> Int? { SpiceScancode.setOne(forMacVirtualKey: k) }

t.test("letters map to set-1 make codes") {
    t.expectEqual(code(MacVirtualKey.a), 0x1E)
    t.expectEqual(code(MacVirtualKey.z), 0x2C)
    t.expectEqual(code(MacVirtualKey.m), 0x32)
    t.expectEqual(code(MacVirtualKey.q), 0x10)
    t.expectEqual(code(MacVirtualKey.p), 0x19)
}

t.test("digit row") {
    t.expectEqual(code(MacVirtualKey.one), 0x02)
    t.expectEqual(code(MacVirtualKey.nine), 0x0A)
    t.expectEqual(code(MacVirtualKey.zero), 0x0B)
}

t.test("control and whitespace keys") {
    t.expectEqual(code(MacVirtualKey.escape), 0x01)
    t.expectEqual(code(MacVirtualKey.returnKey), 0x1C)
    t.expectEqual(code(MacVirtualKey.space), 0x39)
    t.expectEqual(code(MacVirtualKey.delete), 0x0E)        // Backspace
    t.expectEqual(code(MacVirtualKey.tab), 0x0F)
}

t.test("left-hand modifiers are non-extended") {
    t.expectEqual(code(MacVirtualKey.control), 0x1D)
    t.expectEqual(code(MacVirtualKey.shift), 0x2A)
    t.expectEqual(code(MacVirtualKey.option), 0x38)
    t.expectEqual(code(MacVirtualKey.capsLock), 0x3A)
    for k in [MacVirtualKey.control, MacVirtualKey.shift, MacVirtualKey.option] {
        t.expect(!SpiceScancode.isExtended(code(k)!), "\(hex(Int(k))) should not be extended")
    }
}

t.test("right-hand modifiers and GUI are extended") {
    t.expectEqual(code(MacVirtualKey.rightControl), 0xE01D)
    t.expectEqual(code(MacVirtualKey.rightOption), 0xE038)
    t.expectEqual(code(MacVirtualKey.rightCommand), 0xE05C)
    t.expectEqual(code(MacVirtualKey.command), 0xE05B)     // left GUI
    t.expect(SpiceScancode.isExtended(0xE05B), "GUI should be extended")
}

t.test("function keys F1-F12") {
    t.expectEqual(code(MacVirtualKey.f1), 0x3B)
    t.expectEqual(code(MacVirtualKey.f10), 0x44)
    t.expectEqual(code(MacVirtualKey.f11), 0x57)
    t.expectEqual(code(MacVirtualKey.f12), 0x58)
}

t.test("arrow keys are extended with correct make codes") {
    t.expectEqual(code(MacVirtualKey.upArrow), 0xE048)
    t.expectEqual(code(MacVirtualKey.downArrow), 0xE050)
    t.expectEqual(code(MacVirtualKey.leftArrow), 0xE04B)
    t.expectEqual(code(MacVirtualKey.rightArrow), 0xE04D)
    for k in [MacVirtualKey.upArrow, MacVirtualKey.downArrow, MacVirtualKey.leftArrow, MacVirtualKey.rightArrow] {
        t.expect(SpiceScancode.isExtended(code(k)!), "arrow should be extended")
    }
}

t.test("navigation cluster is extended") {
    t.expectEqual(code(MacVirtualKey.home), 0xE047)
    t.expectEqual(code(MacVirtualKey.end), 0xE04F)
    t.expectEqual(code(MacVirtualKey.pageUp), 0xE049)
    t.expectEqual(code(MacVirtualKey.pageDown), 0xE051)
    t.expectEqual(code(MacVirtualKey.help), 0xE052)          // Insert
    t.expectEqual(code(MacVirtualKey.forwardDelete), 0xE053) // Delete
}

t.test("keypad: numbers non-extended, Enter/Divide extended") {
    t.expectEqual(code(MacVirtualKey.keypad0), 0x52)
    t.expectEqual(code(MacVirtualKey.keypad7), 0x47)
    t.expectEqual(code(MacVirtualKey.keypadClear), 0x45)     // NumLock
    t.expectEqual(code(MacVirtualKey.keypadEnter), 0xE01C)
    t.expectEqual(code(MacVirtualKey.keypadDivide), 0xE035)
    t.expect(!SpiceScancode.isExtended(code(MacVirtualKey.keypad0)!), "keypad 0 not extended")
    t.expect(SpiceScancode.isExtended(code(MacVirtualKey.keypadEnter)!), "keypad enter extended")
}

t.test("make/break byte expansion") {
    // Plain key: Escape
    t.expectEqual(SpiceScancode.makeBytes(0x01), [0x01])
    t.expectEqual(SpiceScancode.breakBytes(0x01), [0x81])
    // Extended key: Right arrow 0xE04D
    t.expectEqual(SpiceScancode.makeBytes(0xE04D), [0xE0, 0x4D])
    t.expectEqual(SpiceScancode.breakBytes(0xE04D), [0xE0, 0xCD])
}

t.test("CocoaSpice 0x100 extended encoding (CSInput.sendKey:code:)") {
    // Plain keys: bare make byte.
    t.expectEqual(SpiceScancode.cocoaSpiceEncoded(0x01), 0x01)        // Esc
    t.expectEqual(SpiceScancode.cocoaSpiceEncoded(0x1E), 0x1E)        // A
    // Extended keys: 0xE0NN -> 0x1NN.
    t.expectEqual(SpiceScancode.cocoaSpiceEncoded(0xE04D), 0x14D)     // Right arrow
    t.expectEqual(SpiceScancode.cocoaSpiceEncoded(0xE01D), 0x11D)     // Right Ctrl
    t.expectEqual(SpiceScancode.cocoaSpiceEncoded(0xE01C), 0x11C)     // Keypad Enter
    // End-to-end from a mac key code.
    t.expectEqual(SpiceScancode.cocoaSpiceCode(forMacVirtualKey: MacVirtualKey.rightArrow), 0x14D)
    t.expectEqual(SpiceScancode.cocoaSpiceCode(forMacVirtualKey: MacVirtualKey.escape), 0x01)
    t.expect(SpiceScancode.cocoaSpiceCode(forMacVirtualKey: 0xFE) == nil, "unmapped -> nil")
}

t.test("unmapped keys return nil") {
    t.expect(code(0xFE) == nil, "0xFE should be unmapped")
}

t.test("only Caps Lock produces a lock-key edge from flagsChanged") {
    t.expectEqual(
        SpiceKeyboardRouting.lockKeyTransitions(forFlagsChanged: MacVirtualKey.capsLock),
        [.press(MacVirtualKey.capsLock), .release(MacVirtualKey.capsLock)]
    )
}

t.test("synthetic flagsChanged key code zero does not inject A") {
    t.expectEqual(
        SpiceKeyboardRouting.lockKeyTransitions(forFlagsChanged: MacVirtualKey.a),
        []
    )
}

t.test("ordinary non-modifier flagsChanged events are ignored") {
    t.expectEqual(
        SpiceKeyboardRouting.lockKeyTransitions(forFlagsChanged: MacVirtualKey.p),
        []
    )
}

t.test("spurious flagsChanged events cannot reconcile partial modifier flags") {
    t.expect(SpiceKeyboardRouting.handlesFlagsChanged(MacVirtualKey.shift),
             "real modifier transitions must still be handled")
    t.expect(SpiceKeyboardRouting.handlesFlagsChanged(MacVirtualKey.capsLock),
             "Caps Lock edges must still be handled")
    t.expect(!SpiceKeyboardRouting.handlesFlagsChanged(MacVirtualKey.a),
             "synthetic key-code-zero/A flagsChanged must be ignored before reconciliation")
    t.expect(!SpiceKeyboardRouting.handlesFlagsChanged(MacVirtualKey.period),
             "ordinary punctuation flagsChanged must not alter held modifiers")
}

t.test("PID-zero hardware events stay on the physical route") {
    t.expect(!SpiceKeyboardRouting.usesSyntheticModifierChord(sourcePID: 0),
             "hardware source PID 0 must not synthesize modifiers")
}

t.test("only positive source PIDs use the synthetic modifier route") {
    t.expect(SpiceKeyboardRouting.usesSyntheticModifierChord(sourcePID: 38250),
             "Computer Use source PID must synthesize modifiers")
    t.expect(!SpiceKeyboardRouting.usesSyntheticModifierChord(sourcePID: nil),
             "an NSEvent without a CGEvent must stay physical")
    t.expect(!SpiceKeyboardRouting.usesSyntheticModifierChord(sourcePID: -1),
             "invalid source metadata must stay physical")
}

t.test("synthetic shifted key becomes a balanced guest chord") {
    let down = SpiceKeyboardRouting.syntheticKeyDownTransitions(
        keyCode: MacVirtualKey.four,
        requestedModifiers: [MacVirtualKey.shift]
    )
    t.expectEqual(down.transitions, [.press(MacVirtualKey.shift), .press(MacVirtualKey.four)])
    t.expectEqual(
        SpiceKeyboardRouting.syntheticKeyUpTransitions(
            keyCode: MacVirtualKey.four, ownedModifiers: down.ownedModifiers
        ),
        [.release(MacVirtualKey.four), .release(MacVirtualKey.shift)]
    )
}

t.test("synthetic control chord is balanced") {
    let down = SpiceKeyboardRouting.syntheticKeyDownTransitions(
        keyCode: MacVirtualKey.c,
        requestedModifiers: [MacVirtualKey.control]
    )
    t.expectEqual(down.transitions, [.press(MacVirtualKey.control), .press(MacVirtualKey.c)])
    t.expectEqual(
        SpiceKeyboardRouting.syntheticKeyUpTransitions(
            keyCode: MacVirtualKey.c, ownedModifiers: down.ownedModifiers
        ),
        [.release(MacVirtualKey.c), .release(MacVirtualKey.control)]
    )
}

t.test("synthetic control-shift-C preserves Shift for the entire C stroke") {
    let down = SpiceKeyboardRouting.syntheticKeyDownTransitions(
        keyCode: MacVirtualKey.c,
        requestedModifiers: [MacVirtualKey.control, MacVirtualKey.shift]
    )
    t.expectEqual(
        down.transitions,
        [
            .press(MacVirtualKey.control),
            .press(MacVirtualKey.shift),
            .press(MacVirtualKey.c),
        ]
    )
    t.expectEqual(
        SpiceKeyboardRouting.syntheticKeyUpTransitions(
            keyCode: MacVirtualKey.c, ownedModifiers: down.ownedModifiers
        ),
        [
            .release(MacVirtualKey.c),
            .release(MacVirtualKey.shift),
            .release(MacVirtualKey.control),
        ]
    )
}

t.test("synthetic plain key preserves its physical key code") {
    let down = SpiceKeyboardRouting.syntheticKeyDownTransitions(
        keyCode: MacVirtualKey.keypad0,
        requestedModifiers: []
    )
    t.expectEqual(down.transitions, [.press(MacVirtualKey.keypad0)])
    t.expectEqual(down.ownedModifiers, [])
}

t.test("synthetic chord does not own a physically held modifier") {
    let down = SpiceKeyboardRouting.syntheticKeyDownTransitions(
        keyCode: MacVirtualKey.a,
        requestedModifiers: [MacVirtualKey.shift],
        heldModifiers: [MacVirtualKey.shift]
    )
    t.expectEqual(down.transitions, [.press(MacVirtualKey.a)])
    t.expectEqual(down.ownedModifiers, [])
}

t.test("synthetic multi-modifier releases in reverse order") {
    let down = SpiceKeyboardRouting.syntheticKeyDownTransitions(
        keyCode: MacVirtualKey.c,
        requestedModifiers: [MacVirtualKey.control, MacVirtualKey.shift]
    )
    t.expectEqual(
        SpiceKeyboardRouting.syntheticKeyUpTransitions(
            keyCode: MacVirtualKey.c, ownedModifiers: down.ownedModifiers
        ),
        [.release(MacVirtualKey.c), .release(MacVirtualKey.shift), .release(MacVirtualKey.control)]
    )
}

t.test("all scancodes are unique (no accidental duplicate make codes)") {
    let values = Array(SpiceScancode.table.values)
    let unique = Set(values)
    t.expectEqual(values.count, unique.count)
    t.expect(values.count >= 90, "expected a broad mapping, got \(values.count) entries")
}

t.finishAndExit()
