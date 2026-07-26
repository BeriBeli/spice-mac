# Swift 6 + SwiftUI Migration Plan

## Objective

Migrate SpiceMac to the Swift 6 language mode and a SwiftUI-owned application
lifecycle while preserving the proven CocoaSpice, Metal, input, cursor,
clipboard, audio, and USB behavior.

This migration deliberately targets macOS 26 and later. Compatibility shims for
older SwiftUI or Observation releases are out of scope.

## Target Architecture

```text
SpiceMacApp (SwiftUI App)
├── launcher and session WindowGroup scenes
├── Commands and Settings scenes
├── AppDelegate (@MainActor, @Observable URL inbox only)
└── SessionModel (@MainActor, @Observable; one per window)
    ├── SpiceClient / CocoaSpice callbacks
    └── SpiceDisplayRepresentable (NSViewRepresentable)
        └── SpiceDisplayView (MTKView)
            ├── CSMetalRenderer
            ├── SpiceInputRouter
            └── native cursor and first-responder handling
```

SwiftUI owns scene creation, user-visible state, preferences, commands, and
session lifetime. AppKit remains only where SwiftUI does not expose the required
primitive: `MTKView`, raw `NSEvent` delivery, cursor rectangles, first responder,
backing-pixel conversion, and narrowly scoped window notifications.

## Migration Stages

### 1. Swift 6 baseline

- Raise first-party SwiftPM manifests to Swift tools 6 and macOS 26.
- Compile all first-party targets in Swift 6 language mode.
- Establish explicit main-actor ownership for AppKit and UI state.
- Isolate Objective-C delegate/KVO callbacks at a documented boundary.
- Keep the vendored CocoaSpice manifest unchanged unless a build requirement
  makes an update necessary.

### 2. State ownership

- Introduce a narrow observable URL inbox for Finder/command-line `.vv` opens.
- Introduce one session model per window.
- Keep connection/runtime objects out of SwiftUI value state.
- Replace global mutable menu state with focused scene state.

### 3. SwiftUI application chrome

- Replace the manual `NSApplication.run()` entry point with `SwiftUI.App`.
- Replace programmatic application menus with `Commands`.
- Add a dedicated `Settings` scene backed by `@AppStorage`.
- Use SwiftUI scenes for launcher and independent session windows.
- Preserve opening `.vv` files from Finder, the command line, drag and drop, and
  the Open command.

### 4. Narrow AppKit bridge

- Host `SpiceDisplayView` through a small `NSViewRepresentable`.
- Keep the representable idempotent when SwiftUI updates or recreates it.
- Keep first-responder, live-resize completion, full-screen transitions, and
  backing-scale changes at the bridge/window boundary.
- Do not move SPICE rendering or raw input delivery into SwiftUI gestures.

### 5. Regression and cleanup

- Remove superseded AppKit window/menu code.
- Update architecture, requirements, build, and test documentation.
- Run automated checks and record manual real-VM validation.

## Final Acceptance Requirements

The migration is complete only when all of the following are true.

### Build and language

- Every first-party manifest uses Swift tools 6.2 or later and targets macOS 26.
- The main application compiles in Swift 6 language mode with no concurrency
  errors or first-party compiler warnings.
- Release app assembly, Metal shader compilation, signing, and packaging succeed
  using the project build script.

### Architecture

- `SwiftUI.App` owns the application lifecycle.
- SwiftUI scenes own launcher, settings, and session windows.
- The launcher is a singleton `Window`; terminal session handling cannot create
  duplicate launcher windows or automatically reopen the file picker.
- Each session window owns independent observable session state.
- No global mutable `NSMenu`, `NSWindow`, or active-session singleton remains.
- AppKit interop is limited to documented platform gaps.

### Functional behavior

- Opening one or multiple `.vv` files creates independent sessions.
- Finder open, drag/drop, command-line open, and File > Open work.
- Connection states and failures are visible and do not leave stale sessions.
- A remote disconnect, connection failure, or invalid connection file closes the
  expired session window and returns focus to the launcher. Failure details move
  to the launcher; explicitly closing a session window does not reopen it.
- Full screen, live resize, Retina scaling, and guest dynamic resolution work.
- Keyboard, modifiers, mouse buttons, motion, scrolling, and cursor release work.
- Native/overlay guest cursor behavior remains single-path and aligned.
- Clipboard preference changes apply immediately to active sessions.
- USB device state and connect/disconnect errors are exposed in the focused
  session's commands or UI.
- Closing a window releases input, disconnects the client, detaches rendering,
  and releases the session.

### Automated verification

- VVConfig: 25 checks pass.
- SpiceInputMap: 17 checks pass.
- SpiceClipboardLogic: 4 tests pass.
- SpiceCursorLogic: 9 tests pass.
- Native stutter and worker lifecycle checks pass when staged frameworks are
  available.
- New tests cover session cleanup and command enablement independently of views.

### Manual release evaluation

- A real Proxmox VM completes connect, display, keyboard, mouse, cursor,
  clipboard, audio, resize, full-screen, and disconnect smoke tests.
- USB is tested with at least one redirectable device, or the environment
  limitation and observed error path are recorded.
- Instruments or equivalent observation shows no sustained frame/input latency
  growth during a 30-minute session.
- [x] A packaged app is launched from outside the build directory and re-tested
  for file opening and embedded framework/resource loading.

## Effort and Risk

Expected implementation effort is four to seven engineering days:

| Workstream | Estimate |
| --- | ---: |
| Swift 6 isolation and Objective-C boundaries | 1-2 days |
| SwiftUI scenes, state, commands, and settings | 1.5-2 days |
| Metal/AppKit bridge and window lifecycle | 0.5-1 day |
| Automated and real-VM regression | 1-2 days |

The highest-risk area is not SwiftUI rendering. It is proving that Objective-C
callbacks, KVO values, and USB/cursor objects cross onto the main actor without
races or lifetime regressions.

## Progress Record

- [x] Migration plan and acceptance requirements defined.
- [x] Swift 6/macOS 26 baseline builds.
- [x] SwiftUI lifecycle and scenes implemented.
- [x] AppKit bridge reduced to the documented boundary.
- [x] Automated acceptance checks pass.
- [ ] Manual release evaluation completed.

### 2026-07-26 implementation snapshot

- First-party manifests use Swift tools 6.2, macOS 26, and an explicit Swift 6
  language mode.
- The `SpiceMac` target compiles without Swift 6 concurrency diagnostics.
- SwiftUI owns the application lifecycle, launcher/session scenes, settings,
  commands, focused-session actions, and observable session state.
- `SpiceDisplayRepresentable` is the sole view bridge; it retains the existing
  `MTKView`, raw input, cursor, and backing-pixel behavior.
- All 58 dependency-light checks pass (VVConfig 25, SpiceInputMap 17,
  SpiceClipboardLogic 4, SpiceCursorLogic 9, SpiceSessionLogic 3).
- Session lifecycle tests pin one-shot startup, idempotent cleanup, remote
  disconnect navigation, and focused-input command enablement independently of
  SwiftUI views.
- Remote disconnect, connection failure, and invalid connection files return to
  the launcher and dismiss the expired session. Failure details remain visible
  on the launcher; window-initiated teardown does not reopen it.
- The singleton launcher embeds the Ravada site with macOS 26's native SwiftUI
  `WebView`/`WebPage`. A navigation decider intercepts authenticated `.vv`
  responses without a Save panel, validates them, starts the session, and
  removes temporary files on both startup and parse failure.
- The pinned sysroot and Metal toolchain were installed outside the sandbox.
- A complete release build passed: link, Metal shader compilation, app assembly,
  framework embedding, ad-hoc signing, codesign verification, and zip packaging.
- A clean, non-incremental Release build compiles Swift, Objective-C, and Metal
  sources without compiler warnings.
- Native regression checks pass (stutter 7, worker lifecycle 2), and the packaged
  app launches successfully from outside the build directory with `.vv` opening
  and embedded resources verified. The remaining manual acceptance is real-VM,
  USB-device, Ravada login/download handoff, and 30-minute performance validation.
