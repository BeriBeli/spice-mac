// swift-tools-version:5.9
import PackageDescription

// SpiceMac — a native macOS SPICE client that opens Proxmox VE `.vv` consoles by
// wrapping (a forked) CocoaSpice.
//
// BUILD REQUIREMENTS:
//  * Full Xcode (not just Command Line Tools): CocoaSpice's renderer compiles a
//    .metal shader, which needs the Metal toolchain that only ships with Xcode.
//  * The native SPICE frameworks must be staged under ./Frameworks first:
//        ./scripts/fetch-sysroot.sh
//  * Build & bundle into SpiceMac.app with:  ./scripts/build-app.sh
//
// The pure-Swift libraries (VVConfig, SpiceInputMap) build and test on their own
// with just the toolchain — see their packages under Packages/.

// CocoaSpice's documented native link contract (mirrors its own test target),
// plus the search path and @rpath entries so the bundled .app finds the
// frameworks at runtime. Adjust the library names here if the fetched sysroot
// packages them differently (e.g. as *.framework bundles).
let nativeSpiceLinkerSettings: [LinkerSetting] = [
    .unsafeFlags([
        "-F", "Frameworks",
        "-L", "Frameworks",
        "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
        "-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks",
    ]),
    .linkedLibrary("glib-2.0"),
    .linkedLibrary("gstreamer-1.0"),
    .linkedLibrary("spice-client-glib-2.0"),
    .linkedLibrary("usb-1.0"),
]

let package = Package(
    name: "SpiceMac",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "SpiceMac", targets: ["SpiceMac"]),
    ],
    dependencies: [
        .package(path: "Packages/VVConfig"),
        .package(path: "Packages/SpiceInputMap"),
        .package(path: "ThirdParty/CocoaSpice"),
    ],
    targets: [
        // Swift glue: connection lifecycle, CSConnectionDelegate, NSEvent→CSInput,
        // pasteboard bridge. Depends on the (forked) CocoaSpice ObjC layer.
        .target(
            name: "SpiceController",
            dependencies: [
                .product(name: "VVConfig", package: "VVConfig"),
                .product(name: "SpiceInputMap", package: "SpiceInputMap"),
                .product(name: "CocoaSpice", package: "CocoaSpice"),
                .product(name: "CocoaSpiceRenderer", package: "CocoaSpice"),
            ],
            path: "Packages/SpiceController/Sources/SpiceController"
        ),
        // The AppKit/SwiftUI application.
        .executableTarget(
            name: "SpiceMac",
            dependencies: [
                "SpiceController",
                .product(name: "VVConfig", package: "VVConfig"),
                .product(name: "SpiceInputMap", package: "SpiceInputMap"),
                .product(name: "CocoaSpice", package: "CocoaSpice"),
                .product(name: "CocoaSpiceRenderer", package: "CocoaSpice"),
            ],
            path: "Sources/SpiceMac",
            linkerSettings: nativeSpiceLinkerSettings
        ),
    ]
)
