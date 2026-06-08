# Contributing to SpiceMac

Thanks for your interest! SpiceMac is a native macOS SPICE client for Proxmox VE.

## Ground rules

- Be respectful — see [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
- By contributing, you agree your changes are licensed under the project's
  [MIT License](LICENSE).
- Keep the dependency-free test runners green (CI runs them).

## Project layout

| Path | What |
|------|------|
| `Sources/SpiceMac` | AppKit/Metal app |
| `Packages/SpiceController` | connection lifecycle, input, clipboard glue |
| `Packages/VVConfig`, `Packages/SpiceInputMap` | pure-Swift, unit-tested |
| `ThirdParty/CocoaSpice` | vendored Apache-2.0 fork (Proxmox patch + security fixes) |

## Building & testing

The pure-Swift libraries build and test with just the toolchain (no Xcode/sysroot):

```sh
( cd Packages/VVConfig      && swift run vvcheck )    # .vv parser
( cd Packages/SpiceInputMap && swift run inputcheck ) # keycode→scancode map
```

The full app needs **Xcode** (Metal toolchain), the **Metal toolchain component**
(`xcodebuild -downloadComponent MetalToolchain`), and the native SPICE frameworks:

```sh
SPICEMAC_SYSROOT_URL=… SPICEMAC_SYSROOT_SHA256=… ./scripts/fetch-sysroot.sh
./scripts/upgrade-openssl.sh          # OpenSSL 1.1.1b → 1.1.1w (see SECURITY.md)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh
```

See [README.md](README.md) for details.

## Touching the vendored fork

`ThirdParty/CocoaSpice` is a fork. If you change it, **record the change in
`ThirdParty/CocoaSpice/FORK-NOTES.md`** so it survives a rebase onto upstream. Keep
fork changes minimal and well-justified (the Proxmox patch + the security fixes are
the existing ones).

## Pull requests

- Keep PRs focused; explain the "why".
- Run the two check runners (`vvcheck` / `inputcheck`) and, for native changes,
  `clang -fsyntax-only` over the patched ObjC if relevant.
- Note any security implications — see [SECURITY.md](SECURITY.md).
