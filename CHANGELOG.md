# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] — 2026-06-08

First public release. A native macOS (Apple Silicon) SPICE client that opens
Proxmox VE consoles from `.vv` files, rendering through Metal over a forked
CocoaSpice.

### Added

- **Display** — Metal-rendered SPICE display with aspect-fit scaling, live window
  resize, and dynamic guest resolution (requires `spice-vdagent`).
- **Keyboard** — full keymap (macOS keycode → PC set-1 scancodes, `0xE0`
  extended), including ⌘/modifiers with self-healing on missed key-up, Caps Lock,
  and Ctrl-Alt-Del / Release-Cursor menu commands.
- **Mouse & cursor** — absolute/relative motion, scroll, buttons; guest cursor
  aligned to the macOS pointer; optional hide-Mac-cursor (View menu, off by
  default).
- **Clipboard** — bidirectional text sharing between Mac and guest, on by default
  with a Connection-menu toggle and a 64 MB transfer cap.
- **Audio** — guest audio playback (requires a SPICE audio device on the VM).
- **USB redirection** — Connection ▸ USB Devices picker; documented the macOS
  device-capture gate and shipped `scripts/run-as-root.sh` for kernel-claimed
  devices.
- **Proxmox connection** — `.vv` parser (opaque host token, proxy, tls-port,
  one-time ticket, host-subject, CA), connecting over TLS through the node's
  `spiceproxy` with certificate-subject verification.
- **Forked CocoaSpice** — adds `-[CSConnection setProxy:ca:certSubject:]` (the one
  method needed for Proxmox's proxy + subject-verify TLS); see
  `ThirdParty/CocoaSpice/FORK-NOTES.md`.
- **Tooling** — `scripts/fetch-sysroot.sh` (pinned, checksummed native frameworks),
  `scripts/build-app.sh` (compiles the Metal shader, bundles only the runtime
  closure), and dependency-free test runners (`vvcheck`, `inputcheck`).

### Security

- Upgraded the bundled OpenSSL from the EOL 1.1.1b to **1.1.1w**
  (`scripts/upgrade-openssl.sh`), fixing CVE-2022-0778.
- TLS fails closed: a TLS+subject-verify connection with no CA is rejected.
- Fixed display channel DoS crashes (multi-head `g_assert`, non-UTF8 clipboard).
- Bundle only the 26-framework runtime closure — the upstream sysroot's GPL-2.0
  QEMU frameworks are no longer shipped (app size 443 MB → 23 MB).
- See [SECURITY.md](SECURITY.md) for the threat model and residual risks.

[Unreleased]: https://github.com/Ching367436/spice-mac/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Ching367436/spice-mac/releases/tag/v0.1.0
