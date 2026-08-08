<p align="center">
  <img src="design/icon/icon.png?v=0.2.1-r2" width="168" height="168" alt="Maspice app icon">
</p>

# Maspice

Maspice is a native Apple-Silicon macOS 26+ SPICE client built with SwiftUI,
WebKit, AppKit, Metal, and
[SwiftSpice](https://github.com/BeriBeli/spice-swift).

## Download

Published builds and their release notes are on
[GitHub Releases](https://github.com/BeriBeli/spice-mac/releases). The repository
can be ahead of the newest published asset, so check the release notes for the
backend and supported scope of a particular build.

Each packaged app is accompanied by a SHA-256 file:

```sh
shasum -a 256 -c Maspice.app.zip.sha256
```

Unless a release explicitly says otherwise, the app is ad-hoc signed rather
than Developer-ID signed or notarized. After verifying the checksum, use
**System Settings ▸ Privacy & Security ▸ Open Anyway** if Gatekeeper blocks the
first launch. Never bypass Gatekeeper for an asset whose checksum does not match.

## Supported scope

Maspice connects directly to standard-QEMU and Ravada SPICE endpoints:

- TCP with `host` + `port`;
- TLS with the macOS system trust store, a per-file `ca=`, or `ca=` plus a
  complete `host-subject` validated by SwiftSpice's virt-viewer policy;
- IOSurface/Metal display and cursor presentation;
- ordered keyboard and pointer input;
- audio playback, UTF-8 clipboard sharing, and guest-agent display resizing;
- an embedded Ravada portal that securely hands a downloaded `.vv` file to the
  native session window.

Maspice intentionally rejects non-empty `proxy=` values, opaque
`pvespiceproxy:` hosts, and Proxmox/PVE connection files. It does not expose USB
redirection or microphone capture. The current app presents one display stream
and follows the server-selected mouse mode. Unsupported connection files fail
explicitly instead of falling back to a different transport or trust policy.

## Use

- Enter an HTTPS Ravada portal URL and choose **Open Ravada Portal**. Maspice
  intercepts only user-initiated, same-origin HTTPS `.vv` downloads and removes
  its temporary copy after the session starts.
- Choose **Open Connection File…**, press Command-O, drag a `.vv` file onto the
  launcher, or open the file from Finder. User-supplied files are preserved by
  default; Settings can move them to Trash after connecting.
- Clipboard sharing is enabled by default and can be disabled in Settings for
  an untrusted guest.
- For intermittent input or display lag, use **Session ▸ Show Diagnostics**
  while the session is active. Diagnostics are off by default, keep bounded
  aggregate counters and latency distributions in memory, and include
  content-free VDAgent connection, capability, clipboard, and monitor-request
  state. VDAgent counters cover the current Agent manager lifetime, normally
  the current connection. They do not record endpoint details, credentials,
  key contents, clipboard text, or display pixels. **Copy Summary** writes the
  current aggregate snapshot to the macOS pasteboard only when requested; **Copy Last
  Diagnostics** remains available in the launcher after the session closes.
- Maspice checks for signed updates automatically. Use **Maspice ▸ Check for
  Updates…** for a manual check, or configure automatic checks and downloads in
  **Settings ▸ Updates**.

### Session diagnostics scope

Session Diagnostics is a support aid rather than an end-to-end profiler. Input
send duration ends when the local SwiftSpice send path completes and is not a
server round-trip time. Motion acknowledgements are aggregate signals rather
than per-event RTT samples. Display frame events are observed before final
presentation, and the current snapshot does not measure transport, server,
event-mailbox, or presentation latency. Advanced-video counters cover the
opt-in H.264/H.265 path, not the default MJPEG path.

Intermittent remote-session stalls may not reproduce during release testing.
Release acceptance therefore verifies that Diagnostics remains inactive when
hidden, that enabling it does not cause an obvious input or display regression
in an available live session, and that a stopped or disconnected session can
export its last aggregate summary. When the original stall occurs in the field,
capture that summary together with an approximate time and the observed action;
use Instruments or an external process sample for a complete MainActor deadlock,
because an in-process diagnostics view cannot update while the process is stuck.

## Build from source

Requirements:

- Apple Silicon and macOS 26 or later;
- full Xcode with Swift 6.3 and the macOS 26 SDK;
- the Xcode Metal Toolchain.

```sh
xcodebuild -downloadComponent MetalToolchain
git clone https://github.com/BeriBeli/spice-mac.git
cd spice-mac
swift package resolve
make doctor
make test
make build
```

`make test` exercises `.vv` validation, session policy, the ordered SwiftSpice
input pump, and SwiftUI command registration. `make build` embeds Sparkle and
creates an ad-hoc signed `build/Maspice.app`, zip, and checksum. Use `make run`
to open the staged app and `make distclean` to remove generated app and SwiftPM
state.

SwiftSpice changes belong in its upstream repository. Update Maspice only after
publishing and pinning a reviewed upstream release.

## Distribution gates

The release builder checks dependency install names and runtime search paths in
every Mach-O file before and after app assembly. `/opt/homebrew`, `/usr/local`,
build-tree paths, and other absolute host paths fail the build; Maspice never
uses `install_name_tool` to disguise them. SwiftSpice supplies the arm64 static
XCFrameworks and Metal resource bundle. Sparkle is embedded as a signed,
self-contained framework, and release ZIPs are authenticated with the public
EdDSA key bundled in Maspice.

A successful local build is not complete release evidence. Release acceptance
also requires a clean macOS 26 machine without Homebrew and a live direct
Ravada/standard-QEMU test covering launch, display, audio, input, clipboard,
resize, and the Session Diagnostics enable/copy/stop lifecycle. Reproducing an
intermittent field stall is not a release prerequisite. Developer ID signing,
hardened runtime, and notarization are separate distribution gates.

## Repository layout

| Path | Purpose |
|---|---|
| `Sources/Maspice` | SwiftUI app, Ravada WebKit portal, and narrow AppKit window bridge |
| `Packages/SpiceController` | SwiftSpice lifecycle, agent, audio, and ordered input façade |
| `Packages/VVConfig` | Hardened `.vv` parser and direct-connection policy |
| `Packages/SpiceSessionLogic` | Session lifecycle and command-state policy |
| `scripts` | Environment checks, packaging, link auditing, and release tooling |

## License

Maspice and SwiftSpice are MIT licensed. Native dependency notices are bundled
with every built app. See [LICENSE](LICENSE) and
[THIRD-PARTY-LICENSES.txt](THIRD-PARTY-LICENSES.txt).
