// swift-tools-version:5.5

import PackageDescription

// spice-mac fork addition: suppress upstream CocoaSpice's benign ObjC warnings so
// the host app gets a clean build. No source/logic change.
let quietWarnings = [
    "-Wno-objc-duplicate-category-definition",
    "-Wno-objc-designated-initializers",
    "-Wno-incomplete-implementation",
    "-Wno-return-type",
]

let package = Package(
    name: "CocoaSpice",
    platforms: [
        .iOS(.v11), .macOS(.v10_14)
    ],
    products: [
        .library(
            name: "CocoaSpice",
            targets: ["CocoaSpice"]),
        .library(
            name: "CocoaSpiceNoUsb",
            targets: ["CocoaSpiceNoUsb"]),
        // spice-mac fork addition: expose the renderer so a Swift host app can
        // `import CocoaSpiceRenderer` to construct CSMetalRenderer.
        .library(
            name: "CocoaSpiceRenderer",
            targets: ["CocoaSpiceRenderer"]),
    ],
    targets: [
        .target(
            name: "CocoaSpiceRenderer",
            dependencies: [],
            resources: [
                .process("CSShaders.metal")],
            // spice-mac: silence upstream's benign ObjC warnings for a clean build.
            cSettings: [
                .unsafeFlags(quietWarnings)]),
        .target(
            name: "CocoaSpice",
            dependencies: ["CocoaSpiceRenderer"],
            exclude: ["ExternalHeaders"],
            cSettings: [
                .define("WITH_USB_SUPPORT"),
                .unsafeFlags(quietWarnings),
                .headerSearchPath("ExternalHeaders"),
                .headerSearchPath("ExternalHeaders/glib-2.0"),
                .headerSearchPath("ExternalHeaders/gstreamer-1.0"),
                .headerSearchPath("ExternalHeaders/libusb-1.0"),
                .headerSearchPath("ExternalHeaders/spice-1"),
                .headerSearchPath("ExternalHeaders/spice-client-glib-2.0")]),
        .target(
            name: "CocoaSpiceNoUsb",
            dependencies: ["CocoaSpiceRenderer"],
            exclude: [
                "ExternalHeaders",
                "CSUSBDevice.m",
                "CSUSBManager.m"],
            cSettings: [
                .headerSearchPath("ExternalHeaders"),
                .headerSearchPath("ExternalHeaders/glib-2.0"),
                .headerSearchPath("ExternalHeaders/gstreamer-1.0"),
                .headerSearchPath("ExternalHeaders/spice-1"),
                .headerSearchPath("ExternalHeaders/spice-client-glib-2.0")]),
        .testTarget(
            name: "CocoaSpiceTests",
            dependencies: ["CocoaSpice"],
            linkerSettings: [
                .linkedLibrary("glib-2.0"),
                .linkedLibrary("gstreamer-1.0"),
                .linkedLibrary("usb-1.0"),
                .linkedLibrary("spice-client-glib-2.0")]),
    ]
)
