# Contributing to Maspice

Maspice is a macOS 26+ direct SPICE client for standard QEMU and Ravada.

## Ground rules

- Follow [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
- Contributions are licensed under [LICENSE](LICENSE).
- Do not add Proxmox/PVE, proxy, or USB product paths.
- Send SwiftSpice changes to
  [BeriBeli/spice-swift](https://github.com/BeriBeli/spice-swift), publish a new
  upstream release, and then update Maspice's exact SwiftPM version.
- Do not rewrite Homebrew install names in Maspice. Relocatability must be fixed
  where the SwiftSpice native artifacts are produced.
- Preserve the product boundary: direct TCP/TLS only, no Proxmox/PVE proxy or
  automatic host-resource sharing.

## Layout

| Path | Purpose |
|---|---|
| `Sources/Maspice` | SwiftUI app, Ravada WebKit portal, and AppKit window bridge |
| `Packages/SpiceController` | SwiftSpice lifecycle and ordered input façade |
| `Packages/VVConfig` | `.vv` parser and direct-connection policy |
| `Packages/SpiceSessionLogic` | Session lifecycle and command-state policy |
| `Package.swift` | exact upstream SwiftSpice release dependency |
| `Package.resolved` | reviewed SwiftSpice release revision lock |
| `scripts` | build, packaging, dependency-audit, and release commands |

## Development

Use full Xcode with Swift 6.3, the macOS 26 SDK, and the Metal Toolchain. Install
the last component with `xcodebuild -downloadComponent MetalToolchain`.

```sh
swift package resolve
make doctor
make test
make build
```

Keep pull requests focused and report each kind of evidence separately. Package
tests and a local app build do not replace a live guest test, clean-machine
packaging test, signing check, or benchmark.

For app or native-dependency changes, run `make build` and confirm both the
Mach-O audit and `codesign --verify --deep --strict` pass. The builder must fail
if a selected SwiftSpice release introduces absolute Homebrew or build-host
paths; fix those artifacts upstream rather than rewriting them in Maspice.

## Releases

Add user-facing notes under `## [Unreleased]` in `CHANGELOG.md`. From a clean
`main` branch, maintainers can then run:

```sh
make release VERSION=X.Y.Z
```

The release command updates bundle versions and changelog links, builds and
checks the app, then asks before committing, tagging, pushing, and publishing.
A release still requires live direct Ravada/standard-QEMU acceptance and a
clean macOS 26 machine without Homebrew.
