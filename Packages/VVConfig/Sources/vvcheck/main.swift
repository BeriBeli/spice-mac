// SPDX-License-Identifier: MIT
import Foundation
import VVConfig

// A realistic Proxmox VE spiceproxy file. `\\n` here is the literal two-character
// sequence backslash-n that Proxmox writes into the `ca` value.
let proxmoxSample = """
[virt-viewer]
secure-attention=ctrl+alt+ins
delete-this-file=1
proxy=http://node1.example.com:3128
type=spice
host=pvespiceproxy:1700000000:101:node1::abcdef0123456789==
title=VM 101 - Proxmox
host-subject=OU=PVE Cluster Node,O=Proxmox Virtual Environment,CN=node1.example.com
toggle-fullscreen=shift+f11
release-cursor=shift+f12
password=S3cr3tT1ck3t
tls-port=61000
ca=-----BEGIN CERTIFICATE-----\\nMIIDsampleBase64Line1\\nMIIDsampleBase64Line2\\n-----END CERTIFICATE-----\\n
"""

/// Deterministic PRNG (xorshift64*) so the fuzzer is reproducible — a failing input
/// can be reproduced by re-running, unlike a system RNG.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state >> 12; state ^= state << 25; state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }
    mutating func int(_ upper: Int) -> Int { upper <= 0 ? 0 : Int(next() % UInt64(upper)) }
}

let t = TestRunner()
print("VVConfig checks")

t.test("parses all Proxmox fields") {
    let cfg = try VVConfig.parse(proxmoxSample)
    t.expectEqual(cfg.type, "spice")
    t.expectEqual(cfg.host, "pvespiceproxy:1700000000:101:node1::abcdef0123456789==")
    t.expectNil(cfg.port)
    t.expectEqual(cfg.tlsPort, 61000)
    t.expectEqual(cfg.password, "S3cr3tT1ck3t")
    t.expectEqual(cfg.proxy, "http://node1.example.com:3128")
    t.expectEqual(cfg.title, "VM 101 - Proxmox")
    t.expectEqual(cfg.toggleFullscreen, "shift+f11")
    t.expectEqual(cfg.releaseCursor, "shift+f12")
    t.expectEqual(cfg.secureAttention, "ctrl+alt+ins")
    t.expectEqual(cfg.deleteThisFile, true)
}

t.test("delete-this-file overrides the application fallback") {
    let keep = try VVConfig.parse("[virt-viewer]\ndelete-this-file=0\n")
    let remove = try VVConfig.parse("[virt-viewer]\ndelete-this-file=1\n")
    let unspecified = try VVConfig.parse("[virt-viewer]\ntype=spice\n")
    t.expect(!keep.shouldDeleteThisFile(fallback: true), "explicit 0 must preserve the file")
    t.expect(remove.shouldDeleteThisFile(fallback: false), "explicit 1 must remove the file")
    t.expect(unspecified.shouldDeleteThisFile(fallback: true), "missing key should use fallback")
    t.expect(!unspecified.shouldDeleteThisFile(fallback: false), "missing key should use fallback")
}

t.test("host-subject keeps its '=' signs (split on first '=' only)") {
    let cfg = try VVConfig.parse(proxmoxSample)
    t.expectEqual(cfg.hostSubject,
        "OU=PVE Cluster Node,O=Proxmox Virtual Environment,CN=node1.example.com")
}

t.test("CA escaped newlines are expanded to real newlines") {
    let cfg = try VVConfig.parse(proxmoxSample)
    let ca = try t.unwrap(cfg.caCertificate)
    t.expect(ca.hasPrefix("-----BEGIN CERTIFICATE-----"), "CA should start with PEM header")
    t.expect(ca.contains("\n"), "CA should contain real newlines")
    t.expect(!ca.contains("\\n"), "CA must not contain literal backslash-n")
    t.expect(ca.contains("-----END CERTIFICATE-----"), "CA should contain PEM footer")
    let lines = ca.split(separator: "\n").filter { !$0.isEmpty }
    t.expect(lines.count >= 4, "expected >= 4 PEM lines, got \(lines.count)")
}

t.test("isProxmox is true and validate passes") {
    let cfg = try VVConfig.parse(proxmoxSample)
    t.expect(cfg.isProxmox, "should be detected as Proxmox")
    try cfg.validate()
}

t.test("derived connection parameters for Proxmox") {
    let cfg = try VVConfig.parse(proxmoxSample)
    let p = try SpiceConnectionParameters(from: cfg)
    t.expectEqual(p.host, cfg.host ?? "")
    t.expectEqual(p.tlsPort, 61000)
    t.expectEqual(p.password, "S3cr3tT1ck3t")
    t.expectEqual(p.proxy, "http://node1.example.com:3128")
    t.expectEqual(p.certSubject, "OU=PVE Cluster Node,O=Proxmox Virtual Environment,CN=node1.example.com")
    t.expect(p.verifySubject, "should verify by subject")
    t.expect(p.requiresProxyExtension, "should require the forked proxy extension")
    t.expect(p.isTLS, "should be TLS")
    t.expect(p.caPEM != nil, "should carry the CA PEM")
}

t.test("CRLF line endings handled, no stray CR in values") {
    let crlf = "[virt-viewer]\r\ntype=spice\r\nhost=example.com\r\nport=5900\r\n"
    let cfg = try VVConfig.parse(crlf)
    t.expectEqual(cfg.host, "example.com")
    t.expectEqual(cfg.port, 5900)
    t.expect(!(cfg.host?.contains("\r") ?? false), "host should not contain CR")
}

t.test("comments and blank lines ignored") {
    let text = """
    # a comment
    ; another comment

    [virt-viewer]
      type=spice
    host=example.com
      tls-port=61000

    # trailing comment
    """
    let cfg = try VVConfig.parse(text)
    t.expectEqual(cfg.type, "spice")
    t.expectEqual(cfg.host, "example.com")
    t.expectEqual(cfg.tlsPort, 61000)
}

t.test("keys outside the [virt-viewer] group are ignored") {
    let text = """
    [other]
    host=should-be-ignored.example.com
    [virt-viewer]
    type=spice
    host=real.example.com
    port=5900
    """
    let cfg = try VVConfig.parse(text)
    t.expectEqual(cfg.host, "real.example.com")
}

t.test("plain SPICE file is not Proxmox") {
    let text = "[virt-viewer]\ntype=spice\nhost=10.0.0.5\nport=5900\n"
    let cfg = try VVConfig.parse(text)
    t.expect(!cfg.isProxmox, "plain SPICE should not be Proxmox")
    let p = try SpiceConnectionParameters(from: cfg)
    t.expectEqual(p.host, "10.0.0.5")
    t.expectEqual(p.port, 5900)
    t.expect(!p.verifySubject, "plain should not verify subject")
    t.expect(!p.requiresProxyExtension, "plain should not need proxy extension")
    t.expect(!p.isTLS, "plain should not be TLS")
}

t.test("boolean parsing variants") {
    t.expectEqual(VVConfig.parseBool("1"), true)
    t.expectEqual(VVConfig.parseBool("0"), false)
    t.expectEqual(VVConfig.parseBool("true"), true)
    t.expectEqual(VVConfig.parseBool("FALSE"), false)
    t.expectEqual(VVConfig.parseBool("yes"), true)
    t.expectEqual(VVConfig.parseBool("no"), false)
    t.expectEqual(VVConfig.parseBool("on"), true)
    t.expectEqual(VVConfig.parseBool("off"), false)
    t.expectNil(VVConfig.parseBool("maybe"))
}

// MARK: - Error cases

t.test("missing [virt-viewer] group throws .missingGroup") {
    t.expectThrows(VVConfigError.missingGroup) {
        _ = try VVConfig.parse("type=spice\nhost=x\n")
    }
}

t.test("unsupported type throws .unsupportedType") {
    let cfg = try VVConfig.parse("[virt-viewer]\ntype=vnc\nhost=x\nport=5900\n")
    t.expectThrows(VVConfigError.unsupportedType("vnc")) { try cfg.validate() }
}

t.test("missing port throws .missingPort") {
    let cfg = try VVConfig.parse("[virt-viewer]\ntype=spice\nhost=x\n")
    t.expectThrows(VVConfigError.missingPort) { try cfg.validate() }
}

t.test("missing host throws .missingHost") {
    let cfg = try VVConfig.parse("[virt-viewer]\ntype=spice\ntls-port=61000\n")
    t.expectThrows(VVConfigError.missingHost) { try cfg.validate() }
}

t.test("raw preserves unknown/future keys") {
    let cfg = try VVConfig.parse("[virt-viewer]\ntype=spice\nhost=x\nport=5900\nsome-future-key=42\n")
    t.expectEqual(cfg.raw["some-future-key"], "42")
}

// MARK: - Hardening (the .vv is an attacker-influenced file)

t.test("ports outside 1…65535 (or junk) become nil, not a bogus port") {
    for bad in ["0", "-1", "65536", "70000", "abc", "5900x", "99999999999999999999", " "] {
        let cfg = try VVConfig.parse("[virt-viewer]\ntype=spice\nhost=x\nport=\(bad)\ntls-port=\(bad)\n")
        t.expectNil(cfg.port)
        t.expectNil(cfg.tlsPort)
    }
    for (s, n) in [("1", 1), ("65535", 65535), ("5900", 5900)] {
        let cfg = try VVConfig.parse("[virt-viewer]\ntype=spice\nhost=x\nport=\(s)\n")
        t.expectEqual(cfg.port, n)
    }
    // An out-of-range port with no tls-port is therefore "no port" → missingPort.
    let cfg = try VVConfig.parse("[virt-viewer]\ntype=spice\nhost=x\nport=70000\n")
    t.expectThrows(VVConfigError.missingPort) { try cfg.validate() }
}

t.test("control characters (incl. NUL) are stripped from values — no C-string smuggle") {
    let cfg = try VVConfig.parse("[virt-viewer]\ntype=spice\nhost=good\u{0}evil.example\nport=5900\n")
    let h = try t.unwrap(cfg.host)
    t.expect(!h.unicodeScalars.contains("\u{0}"), "NUL must be stripped")
    // Swift and the C SPICE stack now see the SAME string (no value before the NUL).
    t.expectEqual(h, "goodevil.example")
    let cfg2 = try VVConfig.parse("[virt-viewer]\ntype=spice\nhost=x\nport=5900\npassword=a\u{1}\u{7F}\u{9F}b\n")
    t.expectEqual(cfg2.password, "ab")
}

t.test("a leading UTF-8 BOM does not hide the [virt-viewer] section") {
    let cfg = try VVConfig.parse("\u{FEFF}[virt-viewer]\ntype=spice\nhost=bom.example\nport=5900\n")
    t.expectEqual(cfg.host, "bom.example")
}

t.test("empty / whitespace / section-only inputs throw missingGroup, never crash") {
    for s in ["", "   ", "\n\n\n", "# only a comment\n", "[virt-viewer]\n",
              "[virt-viewer]\n# only comments\n", "[other]\nhost=x\n", "\u{FEFF}"] {
        t.expectThrows(VVConfigError.missingGroup) { _ = try VVConfig.parse(s) }
    }
}

t.test("malformed headers and key/value lines don't crash; '=' handling is correct") {
    for s in ["[]\nhost=x\n", "[\nhost=x\n", "]\nhost=x\n", "[[]]\n=\n=v\nk=\n",
              "[virt-viewer]\n===\nhost=a=b=c\nport=5900\n"] {
        _ = try? VVConfig.parse(s)   // must not crash; result irrelevant
    }
    let cfg = try VVConfig.parse("[virt-viewer]\ntype=spice\nhost=a=b=c\nport=5900\nempty=\n")
    t.expectEqual(cfg.host, "a=b=c")          // split on the FIRST '=' only
    t.expectEqual(cfg.raw["empty"], "")       // empty value kept
}

t.test("duplicate keys: last value wins") {
    let cfg = try VVConfig.parse("[virt-viewer]\ntype=spice\nhost=first\nhost=second\nport=5900\n")
    t.expectEqual(cfg.host, "second")
}

t.test("a very long value within the size cap does not crash") {
    let big = String(repeating: "A", count: 200_000)
    let cfg = try VVConfig.parse("[virt-viewer]\ntype=spice\nhost=\(big)\nport=5900\n")
    t.expectEqual(cfg.host?.count, 200_000)
}

t.test("init(contentsOf:) caps file size, rejects non-UTF-8, and parses a normal file") {
    let dir = FileManager.default.temporaryDirectory
    let big = dir.appendingPathComponent("vv-big-\(UUID().uuidString).vv")
    let bin = dir.appendingPathComponent("vv-bin-\(UUID().uuidString).vv")
    let ok  = dir.appendingPathComponent("vv-ok-\(UUID().uuidString).vv")
    defer { for u in [big, bin, ok] { try? FileManager.default.removeItem(at: u) } }

    try String(repeating: "x", count: VVConfig.maxFileBytes + 4096).write(to: big, atomically: true, encoding: .utf8)
    t.expectThrows(VVConfigError.fileTooLarge) { _ = try VVConfig(contentsOf: big) }

    try Data([0xFF, 0xFE, 0x00, 0x80, 0x81]).write(to: bin)   // invalid UTF-8
    t.expectThrows(VVConfigError.notUTF8) { _ = try VVConfig(contentsOf: bin) }

    try proxmoxSample.write(to: ok, atomically: true, encoding: .utf8)
    let cfg = try VVConfig(contentsOf: ok)
    t.expectEqual(cfg.tlsPort, 61000)
}

t.test("fuzz: 20k arbitrary/mutated inputs never crash the parser or downstream") {
    var rng = SeededRNG(seed: 0x5C0FFEE_C0FFEE)
    let alphabet = Array("[]=\n\r#;: .\\\t/=abcDEF012-_pvespiceproxy host port tls ca\u{0}\u{1}\u{7F}éあ🔒")
    let valid = Array(proxmoxSample)
    for i in 0..<20_000 {
        let s: String
        if i % 3 == 0 {                              // random soup
            var soup = ""
            for _ in 0..<rng.int(220) { soup.append(alphabet[rng.int(alphabet.count)]) }
            s = soup
        } else {                                     // mutate a real Proxmox file
            var chars = valid
            for _ in 0..<(1 + rng.int(8)) where !chars.isEmpty {
                let idx = rng.int(chars.count)
                switch rng.int(3) {
                case 0: chars.remove(at: idx)
                case 1: chars.insert(alphabet[rng.int(alphabet.count)], at: idx)
                default: chars[idx] = alphabet[rng.int(alphabet.count)]
                }
            }
            s = String(chars)
        }
        // Crashing (fatalError / force-unwrap / out-of-bounds) would abort the process
        // and this test would never report — so reaching the end IS the assertion.
        if let cfg = try? VVConfig.parse(s) {
            _ = cfg.isProxmox
            try? cfg.validate()
            _ = try? SpiceConnectionParameters(from: cfg)
        }
    }
    t.expect(true, "completed 20k fuzz iterations without crashing")
}

t.finishAndExit()
