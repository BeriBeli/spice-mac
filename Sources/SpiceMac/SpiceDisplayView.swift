// SPDX-License-Identifier: MIT
import AppKit
import MetalKit
import CocoaSpice
import CocoaSpiceRenderer
import SpiceController
import SpiceCursorLogic

/// The Metal-backed view that renders one SPICE display and is the keyboard/mouse
/// first responder. CocoaSpice draws into it via a `CSMetalRenderer` set as the
/// `MTKView` delegate; AppKit events are forwarded to a `SpiceInputRouter`.
final class SpiceDisplayView: MTKView {

    let router = SpiceInputRouter()
    private var renderer: CSMetalRenderer?
    private(set) weak var attachedDisplay: CSDisplay?

    /// KVO token for the attached display's `displaySize` (guest resolution may
    /// change after the agent connects / a mode switch).
    private var displaySizeObservation: NSKeyValueObservation?

    /// Tracks late cursor-channel attachment and subsequent shape/mode changes.
    private var displayCursorObservation: NSKeyValueObservation?
    private var cursorSnapshotObservation: NSKeyValueObservation?
    private weak var attachedCursor: CSCursor?

    /// The AppKit cursor installed over the SPICE display. In client/absolute
    /// mode this is built from the guest-provided shape; in server/relative mode
    /// it is transparent while CocoaSpice renders the server-positioned overlay.
    private var displayCursor: NSCursor?

    private static let transparentCursor = NSCursor(
        image: NSImage(size: NSSize(width: 1, height: 1)),
        hotSpot: .zero)

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
        // The input router maps a view point -> guest pixel using the SAME fit math
        // the renderer uses, so guest input lands under the native macOS pointer.
        router.viewportInfoProvider = { [weak self] in
            guard let info = self?.viewportInfo() else { return nil }
            return SpiceInputRouter.ViewportInfo(
                guestSize: info.guestSize,
                drawableSize: info.drawableSize,
                scale: info.scale,
                origin: info.origin,
                backingScale: info.backingScale)
        }

        // Recompute the fit whenever the guest changes resolution (post-agent
        // connect, mode switches). Fire once immediately for the current size.
        displaySizeObservation = display.observe(\.displaySize, options: [.initial]) {
            [weak self] _, _ in
            DispatchQueue.main.async { self?.updateViewport() }
        }
        displayCursorObservation = display.observe(\.cursor, options: [.initial, .new]) {
            [weak self] _, change in
            DispatchQueue.main.async { self?.attachCursor(change.newValue ?? nil) }
        }
    }

    func detach() {
        attachCursor(nil)
        displayCursorObservation = nil
        if let attachedDisplay, let renderer {
            attachedDisplay.removeRenderer(renderer)
        }
        displaySizeObservation = nil
        delegate = nil
        renderer = nil
        attachedDisplay = nil
        // NB: do NOT clear router.input here. The inputs channel is independent of
        // the display; its lifecycle is driven by spiceInput{Available,Unavailable}.
        // attachDisplay() calls detach() on every (re)attach (e.g. when the agent
        // connects and the display reconfigures), so clearing input here would
        // silently kill keyboard/mouse while the input channel is still alive.
    }

    // MARK: - Viewport fit (aspect-preserving, centered)

    /// Current backing scale (points -> physical/drawable pixels). Falls back to
    /// the view's `convertToBacking` so it is correct even before `window` is set.
    private var backingScale: CGFloat {
        window?.backingScaleFactor ?? convertToBacking(CGSize(width: 1, height: 1)).width
    }

    /// Snapshot of everything the input router needs to inverse-map a view point
    /// to a guest pixel: the guest size, the drawable size, and the active
    /// fit-scale/origin. All sizes are in DRAWABLE (physical) pixels except
    /// `guestSize`, which is in guest pixels.
    struct ViewportInfo {
        var guestSize: CGSize       // guest pixels (W, H)
        var drawableSize: CGSize    // physical pixels (Dw, Dh)
        var scale: CGFloat          // drawable-pixels per guest-pixel
        var origin: CGPoint         // viewportOrigin, drawable pixels
        var backingScale: CGFloat   // points -> drawable pixels
    }

    func viewportInfo() -> ViewportInfo? {
        guard let guest = attachedDisplay?.displaySize,
              guest.width > 0, guest.height > 0 else { return nil }
        let drawable = drawableSize
        let scale = Self.fitScale(guest: guest, drawable: drawable)
        // We center via viewportOrigin = .zero (the renderer centers the quad).
        return ViewportInfo(guestSize: guest,
                            drawableSize: drawable,
                            scale: scale,
                            origin: .zero,
                            backingScale: backingScale)
    }

    /// Largest uniform scale that fits the guest display inside the drawable
    /// (aspect-preserving "fit with black bars"). Use `max` for cover/fill.
    private static func fitScale(guest: CGSize, drawable: CGSize) -> CGFloat {
        guard guest.width > 0, guest.height > 0,
              drawable.width > 0, drawable.height > 0 else { return 1.0 }
        return min(drawable.width / guest.width, drawable.height / guest.height)
    }

    /// Push the aspect-fit scale to the renderer. Centering is automatic: the
    /// renderer draws the guest quad centered on the drawable, so viewportOrigin
    /// stays .zero and the letterbox bars are split evenly.
    private func updateViewport() {
        guard let renderer, let info = viewportInfo() else { return }
        renderer.viewportScale = info.scale
        renderer.viewportOrigin = .zero
        refreshCursorPresentation()
    }

    // Recompute on any geometry change. `drawableSize` tracks `bounds * backingScale`,
    // so frame resizes and Retina/non-Retina screen moves both land here.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateViewport()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateViewport()
    }

    // MARK: - Responder

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func becomeFirstResponder() -> Bool {
        super.becomeFirstResponder()
    }

    // Grab keyboard focus as soon as we're placed in a window.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            window?.makeFirstResponder(self)
            // Backing scale is now known; refit so we don't draw at the wrong scale.
            updateViewport()
        }
    }

    override func resignFirstResponder() -> Bool {
        // Flush held keys/modifiers/buttons so nothing stays latched in the guest
        // when focus leaves (e.g. Cmd-Tab); also avoids the on-return modifier desync.
        router.releaseAll()
        restoreSystemCursor()
        return super.resignFirstResponder()
    }

    // MARK: - Native guest cursor

    private func attachCursor(_ cursor: CSCursor?) {
        guard attachedCursor !== cursor else { return }
        attachedCursor?.isInhibited = false
        cursorSnapshotObservation = nil
        attachedCursor = cursor
        cursorSnapshotObservation = cursor?.observe(\.snapshot, options: [.initial, .new]) {
            [weak self, weak cursor] _, change in
            guard let snapshot = change.newValue else { return }
            DispatchQueue.main.async {
                guard let self, self.attachedCursor === cursor else { return }
                self.refreshCursorPresentation(using: snapshot)
            }
        }
        if cursor == nil { refreshCursorPresentation() }
    }

    /// Keep exactly one cursor visible. Absolute mode uses an AppKit-native cursor
    /// made from the SPICE shape and inhibits the Metal overlay. Relative mode
    /// keeps the server-positioned overlay and makes the scoped AppKit cursor
    /// transparent.
    func refreshCursorPresentation() {
        guard let cursor = attachedCursor else {
            displayCursor = nil
            window?.invalidateCursorRects(for: self)
            return
        }

        refreshCursorPresentation(using: cursor.snapshot)
    }

    private func refreshCursorPresentation(using snapshot: CSCursorSnapshot) {
        guard let cursor = attachedCursor else { return }
        let serverMode = snapshot.serverModeCursor
        let hidden = snapshot.cursorHidden
        let hasCustomShape = snapshot.cursorImageData != nil
        let decision = SpiceCursorLogic.presentationDecision(
            serverMode: serverMode,
            hidden: hidden,
            hasCustomShape: hasCustomShape,
            windowActive: window?.isKeyWindow == true)
        cursor.isInhibited = decision.inhibitOverlay
        switch decision.hostCursor {
        case .transparent:
            displayCursor = Self.transparentCursor
        case .custom:
            displayCursor = makeNativeCursor(from: snapshot) ?? .arrow
        case .systemDefault:
            displayCursor = .arrow
        }
        window?.invalidateCursorRects(for: self)
    }

    func restoreSystemCursor() {
        NSCursor.arrow.set()
    }

    private func makeNativeCursor(from snapshot: CSCursorSnapshot) -> NSCursor? {
        let width = Int(snapshot.cursorSize.width)
        let height = Int(snapshot.cursorSize.height)
        guard width > 0, height > 0,
              let data = snapshot.cursorImageData,
              let image = SpiceCursorLogic.makeNativeCursorImage(width: width, height: height, data: data)
        else { return nil }

        // Match the renderer's guest-pixel-to-point scale so cursor size remains
        // aligned with a fitted or Retina-backed guest display.
        let pointScale: CGFloat
        if let info = viewportInfo(), info.backingScale > 0 {
            pointScale = info.scale / info.backingScale
        } else {
            pointScale = 1
        }
        let imageSize = NSSize(width: CGFloat(width) * pointScale,
                               height: CGFloat(height) * pointScale)
        let nativeImage = NSImage(cgImage: image, size: imageSize)
        let hotSpot = NSPoint(
            x: min(max(0, snapshot.cursorHotspot.x), CGFloat(width - 1)) * pointScale,
            y: min(max(0, snapshot.cursorHotspot.y), CGFloat(height - 1)) * pointScale
        )
        return NSCursor(image: nativeImage, hotSpot: hotSpot)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if let displayCursor {
            addCursorRect(bounds, cursor: displayCursor)
        }
    }

    override func keyDown(with event: NSEvent) { router.keyDown(event) }
    override func keyUp(with event: NSEvent) { router.keyUp(event) }
    override func flagsChanged(with event: NSEvent) { router.flagsChanged(event) }

    override func mouseDown(with event: NSEvent) {
        // Clicking the guest should also take keyboard focus.
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        router.mouseButton(event, pressed: true)
    }
    override func mouseUp(with event: NSEvent) { router.mouseButton(event, pressed: false) }
    override func rightMouseDown(with event: NSEvent) { router.mouseButton(event, pressed: true) }
    override func rightMouseUp(with event: NSEvent) { router.mouseButton(event, pressed: false) }
    override func otherMouseDown(with event: NSEvent) { router.mouseButton(event, pressed: true) }
    override func otherMouseUp(with event: NSEvent) { router.mouseButton(event, pressed: false) }

    override func mouseMoved(with event: NSEvent) {
        router.mouseMoved(event, in: self)
    }
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
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved],
            owner: self, userInfo: nil)
        addTrackingArea(area)
    }
}
