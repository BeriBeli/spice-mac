# Vendored fork of utmapp/CocoaSpice

This directory is a vendored copy of [utmapp/CocoaSpice](https://github.com/utmapp/CocoaSpice)
(Apache License 2.0 — see `LICENSE`), the Objective-C/Metal SPICE client layer that
UTM uses, with Proxmox support and downstream fixes for **spice-mac**.

## Why a fork is required

`CSConnection` keeps the underlying `SpiceSession *` private (declared only in the
in-`.m` class extension and in `CSSession+Protected.h`, neither of which is public).
Proxmox VE serves SPICE over TLS through the node's `spiceproxy`, which requires the
session be configured with `proxy`, `ca`, `cert-subject`, and subject-based `verify`
— none of which stock CocoaSpice exposes. So the configuration must happen *inside*
the library, where `spiceSession` is reachable.

## The change

A single category method, `-[CSConnection setProxy:ca:certSubject:]`:

- **`Sources/CocoaSpice/include/CSConnection+Proxmox.h`** — new public header (category interface).
- **`Sources/CocoaSpice/CSConnection.m`** — imports the header and implements the method
  (sets `proxy`, the `ca` GByteArray, `cert-subject`, and `verify = SPICE_SESSION_VERIFY_SUBJECT`).
- **`Sources/CocoaSpice/include/CocoaSpice.h`** — includes the new header in the umbrella.

The diff against pristine upstream is saved at `../cocoaspice-proxmox.patch`.

## Security hardening (spice-mac additions)

Beyond the Proxmox patch and the `CocoaSpiceRenderer` product, this fork carries a
few security fixes for guest-triggered crashes / unsafe defaults. Re-apply these
on a rebase:

- **`Sources/CocoaSpice/CSDisplay.m`** (`cs_update_monitor_area`) — replaced
  `g_assert(monitors->len <= 1)` (which aborts the process on a protocol-legal
  multi-head config — a remote DoS) with the upstream find-our-head-by-id loop.
- **`Sources/CocoaSpice/CSConnection.m`** (`cs_display_monitors`) — removed
  `g_assert(cfgs->len == 1)` (same DoS class: a multi-head monitors config from
  a malicious/multi-monitor guest aborted the whole client). The handler only
  needs to know whether the display has any heads (create/update) or none
  (destroy); per-head geometry is resolved by `cs_update_monitor_area`.
- **`Sources/CocoaSpice/include/CSPasteboardDelegate.h`** — `setString:` made
  `nullable` so a guest sending non-UTF8 "text" (→ nil NSString) can't trap the
  Swift bridge.
- **`Sources/CocoaSpice/CSSession.m`** (`initWithSession:`) — removed the
  unconditional `setSharedDirectory:readOnly:NO`, which auto-shared a **writable**
  host folder with every guest.

## Bug fixes (spice-mac additions)

- **`Sources/CocoaSpice/CSDisplay.m` + `CSDisplay+Renderer.m`** — **blank screen on
  connect** (shown only after the guest next repaints, e.g. a click). Two parts:
  - The SPICE main loop runs on its own thread (`CSMain`). A display's primary
    surface is created there (`cs_primary_create` → `updateVisibleAreaWithRect:` →
    `rebuildCanvasTexture`), but the Metal **device** only arrives when a renderer
    attaches — from the app thread, via `-addRenderer:`. On connect the surface is
    usually created *before* the renderer attaches, so `rebuildCanvasTexture`
    early-returns on the nil device and there is no Metal canvas; the renderer then
    draws nothing until a later server damage event. Fix: `-addRenderer:` calls the
    new `-refreshContentsForNewRenderer`, which hops to the SPICE context and, with
    a device now available, builds the canvas (if not yet built) and repaints the
    current framebuffer.
  - In `updateVisibleAreaWithRect:`, build the vertices and set `ready` *before*
    `rebuildCanvasTexture`, so its initial `drawRegion:` sees `-isVisible` YES
    (`_CSRendererSourceData initWithRenderSource:` returns nil when vertices are
    missing, which otherwise drops the first blit) — this covers the case where a
    renderer/device *is* already attached when the surface is (re)created.
- **`Sources/CocoaSpice/CSSession.m`** (`cs_clipboard_grab`) — **guest→host
  clipboard lost all but one representation.** A guest grab is a single clipboard
  offering that can carry several types at once (a copied spreadsheet cell =
  UTF8 text + a bitmap image); CocoaSpice requests every advertised type, and each
  arrives in a separate `cs_clipboard_got_from_guest` call. The macOS pasteboard
  bridge cleared the pasteboard on *every* write, so the types clobbered each other
  and only the last survived (often the image) — pasting the cell's text on the Mac
  got nothing. Fix: `cs_clipboard_grab` now takes ownership of the host pasteboard
  **once** (`[pasteboardDelegate clearContents]`) when the grab arrives, and the
  bridge's `setData:`/`setString:` no longer clear per write, so the representations
  accumulate. (Pairs with the bridge change in
  `Packages/SpiceController/Sources/SpiceController/SpicePasteboardBridge.swift`.)
- **`Sources/CocoaSpice/CSCursor.m` + `include/CSCursor.h`** — atomically publish
  an immutable snapshot of spice-gtk's normalized RGBA cursor pixels, hotspot,
  guest visibility, mouse mode, and revision. The macOS host consumes one coherent
  snapshot as an AppKit `NSCursor` in absolute mode and sets `isInhibited` so Metal
  does not render a second cursor. Cursor-channel teardown explicitly detaches the
  display, and changing inhibition invalidates it immediately.
- **Input scheduling, clipboard requests, and Metal frame handoff** — coalesce
  bursty pointer motion and scroll input before submitting bounded work to the
  SPICE main context; move host pasteboard materialization off the GLib callback
  with generation-scoped caching and bounded reads; and complete canvas uploads
  after the Metal blit rather than after every display has presented. The renderer
  now clears its dirty flag after submission and shares one command queue per
  texture so secondary displays remain GPU-ordered without blocking the producer.

## Updating upstream

To re-base onto a newer CocoaSpice: replace this directory with the new upstream
tree, re-apply `../cocoaspice-proxmox.patch`, then re-apply the security and bug-fix
entries above. The Proxmox patch is intentionally tiny and is a good candidate to
upstream as a PR.
