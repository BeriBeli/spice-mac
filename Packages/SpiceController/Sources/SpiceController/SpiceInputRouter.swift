import AppKit
import CocoaSpice
import SpiceInputMap

/// Translates AppKit `NSEvent`s into CocoaSpice `CSInput` calls. The hosting view
/// forwards its responder events here; this class owns the running button mask,
/// the set of held modifier keys, and the absolute-coordinate transform.
public final class SpiceInputRouter {

    /// The active inputs channel. Set when `spiceInputAvailable:` fires.
    public weak var input: CSInput?

    /// Supplies the current guest display size (pixels) for absolute pointer
    /// mapping. If nil, the view's own bounds size is used.
    public var displaySizeProvider: (() -> CGSize)?

    private var buttonMask: CSInputButton = []
    private var heldModifiers: Set<UInt16> = []

    public init(input: CSInput? = nil) {
        self.input = input
    }

    // MARK: - Keyboard

    public func keyDown(_ event: NSEvent) {
        // Auto-repeats are forwarded as additional presses, which the guest expects.
        sendKey(event.keyCode, pressed: true)
    }

    public func keyUp(_ event: NSEvent) {
        sendKey(event.keyCode, pressed: false)
    }

    /// macOS reports modifier presses/releases as `flagsChanged` without telling
    /// us the direction, so we toggle on a held-set keyed by the modifier's
    /// virtual key code (which distinguishes left/right modifiers).
    public func flagsChanged(_ event: NSEvent) {
        let kc = event.keyCode
        if heldModifiers.contains(kc) {
            heldModifiers.remove(kc)
            sendKey(kc, pressed: false)
        } else {
            heldModifiers.insert(kc)
            sendKey(kc, pressed: true)
        }
    }

    private func sendKey(_ keyCode: UInt16, pressed: Bool) {
        guard let input,
              let code = SpiceScancode.cocoaSpiceCode(forMacVirtualKey: keyCode) else { return }
        input.sendKey(pressed ? .press : .release, code: Int32(code))
    }

    /// Release any keys/modifiers we believe are held (call on focus loss).
    public func releaseAll() {
        input?.releaseKeys()
        heldModifiers.removeAll()
        buttonMask = []
    }

    // MARK: - Mouse

    public func mouseButton(_ event: NSEvent, pressed: Bool) {
        guard let input else { return }
        let b = Self.button(for: event.buttonNumber)
        if pressed { buttonMask.insert(b) } else { buttonMask.remove(b) }
        input.sendMouseButton(b, mask: buttonMask, pressed: pressed)
    }

    public func mouseMoved(_ event: NSEvent, in view: NSView) {
        guard let input else { return }
        if input.serverModeCursor {
            input.sendMouseMotion(buttonMask,
                                  relativePoint: CGPoint(x: event.deltaX, y: event.deltaY))
        } else {
            input.sendMousePosition(buttonMask, absolutePoint: absolutePoint(event, in: view))
        }
    }

    public func scrollWheel(_ event: NSEvent) {
        guard let input else { return }
        let dy = event.scrollingDeltaY
        if event.hasPreciseScrollingDeltas {
            input.sendMouseScroll(.smooth, buttonMask: buttonMask, dy: dy)
        } else if dy > 0 {
            input.sendMouseScroll(.up, buttonMask: buttonMask, dy: 0)
        } else if dy < 0 {
            input.sendMouseScroll(.down, buttonMask: buttonMask, dy: 0)
        }
    }

    /// Map the guest mouse mode the server prefers (server = relative).
    public func requestMouseMode(server: Bool) {
        input?.requestMouseMode(server)
    }

    // MARK: - Helpers

    private func absolutePoint(_ event: NSEvent, in view: NSView) -> CGPoint {
        let local = view.convert(event.locationInWindow, from: nil)
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        let size = displaySizeProvider?() ?? bounds.size
        // AppKit's origin is bottom-left; the SPICE guest framebuffer is top-left.
        let nx = max(0, min(1, local.x / bounds.width))
        let ny = max(0, min(1, 1.0 - local.y / bounds.height))
        return CGPoint(x: nx * size.width, y: ny * size.height)
    }

    private static func button(for buttonNumber: Int) -> CSInputButton {
        switch buttonNumber {
        case 0: return .left
        case 1: return .right
        case 2: return .middle
        case 3: return .side
        default: return .extra
        }
    }
}
