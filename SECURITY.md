# Security

## Supported boundary

Maspice accepts direct SPICE TCP endpoints and direct TLS endpoints validated by
the macOS system trust store or a CA certificate embedded in the connection
file. A custom CA is scoped to that connection and does not modify the system
trust store. When `host-subject` accompanies that CA, SwiftSpice's explicit
virt-viewer policy validates the chain and validity dates and requires the
complete leaf-certificate subject to match. Maspice rejects proxy routing and
Proxmox host tokens before parameters cross into SwiftSpice.

The `.vv` parser caps files at 1 MiB, requires UTF-8, strips control characters,
range-checks ports, and is exercised by deterministic malformed-input tests.

## Ravada portal

The embedded portal upgrades configured URLs to HTTPS. A `.vv` handoff must be
user initiated, use HTTPS, and remain on the configured portal host. Download
cookies are copied only when their domain, path, secure flag, and expiration
match the request; the bounded download itself uses an ephemeral URL session.

For a portal certificate that macOS cannot validate, **Trust Once** is limited
to the current portal session. **Always Trust** stores a SHA-256 certificate
fingerprint for that host; a changed certificate prompts again. Portal
credentials remain inside WebKit and are not read by Maspice.

Downloaded connection files are written to a unique temporary path, parsed
before use, and removed after session startup. User-selected `.vv` files are
preserved by default unless the file directive or user preference requests
deletion.

## Guest-facing surfaces

Display, cursor, audio, clipboard, and guest-agent messages are untrusted network
input. Clipboard sharing can be disabled. Connection files are preserved by
default except for the portal temporary-file path above. Input edges are
serialized and released when the window resigns focus or closes. Maspice does
not automatically select USB devices, smartcards, or host folders.

## Distribution

The pinned SwiftSpice release supplies arm64 static XCFrameworks built from
checksum-pinned sources. The release builder independently rejects
`/opt/homebrew`, `/usr/local`, and other build-host absolute dynamic-library
dependencies; it does not repair them with `install_name_tool`. The current
local build gate also rejects absolute runtime search paths. Passing it is not
proof of a distributable release: clean-Mac launch and live endpoint validation
remain release requirements.

Developer-ID signing, hardened runtime, notarization, dependency-license review,
and live hostile-input testing remain separate release gates.

Report vulnerabilities through
[GitHub private vulnerability reporting](https://github.com/BeriBeli/spice-mac/security/advisories/new).
For non-sensitive bugs, open a normal issue. Never attach a live `.vv` ticket,
password, CA, portal cookie, or certificate-trust record to a public report.
