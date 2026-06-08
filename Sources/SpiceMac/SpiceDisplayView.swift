import AppKit
import MetalKit
import CocoaSpice
import CocoaSpiceRenderer
import SpiceController

/// The Metal-backed view that renders one SPICE display and is the keyboard/mouse
/// first responder. CocoaSpice draws into it via a `CSMetalRenderer` set as the
/// `MTKView` delegate; AppKit events are forwarded to a `SpiceInputRouter`.
final class SpiceDisplayView: MTKView {

    let router = SpiceInputRouter()
    private var renderer: CSMetalRenderer?
    private(set) weak var attachedDisplay: CSDisplay?

    init() {
        // CSMetalRenderer reads `mtkView.device` at init, so the device must exist
        // before -attachDisplay creates the renderer.
        super.init(frame: NSRect(x: 0, y: 0, width: 1024, height: 768),
                   device: MTLCreateSystemDefaultDevice())
        commonInit()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        if device == nil { device = MTLCreateSystemDefaultDevice() }
        commonInit()
    }

    private func commonInit() {
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = false
        // Frames are pushed by CocoaSpice; run continuously so the latest texture
        // is always presented.
        isPaused = false
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 60
        wantsLayer = true
        layer?.isOpaque = true
    }

    func attachDisplay(_ display: CSDisplay) {
        detach()
        attachedDisplay = display
        let renderer = CSMetalRenderer(metalKitView: self)
        delegate = renderer
        self.renderer = renderer
        display.addRenderer(renderer)
        router.displaySizeProvider = { [weak display] in display?.displaySize ?? .zero }
        // In client mouse mode we must position the guest cursor overlay ourselves.
        router.cursorMover = { [weak display] point in display?.cursor?.move(to: point) }
    }

    func detach() {
        if let attachedDisplay, let renderer {
            attachedDisplay.removeRenderer(renderer)
        }
        delegate = nil
        renderer = nil
        attachedDisplay = nil
        // NB: do NOT clear router.input here. The inputs channel is independent of
        // the display; its lifecycle is driven by spiceInput{Available,Unavailable}.
        // attachDisplay() calls detach() on every (re)attach (e.g. when the agent
        // connects and the display reconfigures), so clearing input here would
        // silently kill keyboard/mouse while the input channel is still alive.
    }

    // MARK: - Responder

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        spiceInputLog("becomeFirstResponder -> \(ok)")
        return ok
    }

    // Grab keyboard focus as soon as we're placed in a window.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { window?.makeFirstResponder(self) }
    }

    override func resignFirstResponder() -> Bool {
        // Flush held keys/modifiers/buttons so nothing stays latched in the guest
        // when focus leaves (e.g. Cmd-Tab); also avoids the on-return modifier desync.
        router.releaseAll()
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        spiceInputLog("keyDown keyCode=\(event.keyCode) isFirstResponder=\(window?.firstResponder === self) hasInput=\(router.input != nil)")
        router.keyDown(event)
    }
    override func keyUp(with event: NSEvent) { router.keyUp(event) }
    override func flagsChanged(with event: NSEvent) { router.flagsChanged(event) }

    override func mouseDown(with event: NSEvent) {
        // Clicking the guest should also take keyboard focus.
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        spiceInputLog("mouseDown hasInput=\(router.input != nil)")
        router.mouseButton(event, pressed: true)
    }
    override func mouseUp(with event: NSEvent) { router.mouseButton(event, pressed: false) }
    override func rightMouseDown(with event: NSEvent) { router.mouseButton(event, pressed: true) }
    override func rightMouseUp(with event: NSEvent) { router.mouseButton(event, pressed: false) }
    override func otherMouseDown(with event: NSEvent) { router.mouseButton(event, pressed: true) }
    override func otherMouseUp(with event: NSEvent) { router.mouseButton(event, pressed: false) }

    override func mouseMoved(with event: NSEvent) { router.mouseMoved(event, in: self) }
    override func mouseDragged(with event: NSEvent) { router.mouseMoved(event, in: self) }
    override func rightMouseDragged(with event: NSEvent) { router.mouseMoved(event, in: self) }
    override func otherMouseDragged(with event: NSEvent) { router.mouseMoved(event, in: self) }
    override func scrollWheel(with event: NSEvent) { router.scrollWheel(event) }

    // Deliver mouseMoved while the window is key.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self, userInfo: nil)
        addTrackingArea(area)
    }
}
