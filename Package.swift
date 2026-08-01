// swift-tools-version:6.3
import PackageDescription

// Maspice consumes an exact upstream SwiftSpice release. A Maspice release is
// allowed only when that version provides a relocatable native dependency
// closure; the application does not rewrite Homebrew install names itself.

let package = Package(
    name: "Maspice",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Maspice", targets: ["Maspice"]),
    ],
    dependencies: [
        .package(path: "Packages/VVConfig"),
        .package(path: "Packages/SpiceSessionLogic"),
        .package(
            url: "https://github.com/BeriBeli/spice-swift.git",
            exact: "0.1.2"
        ),
    ],
    targets: [
        // Swift glue around the SwiftSpice session, input, audio, and agent APIs.
        .target(
            name: "SpiceController",
            dependencies: [
                .product(name: "VVConfig", package: "VVConfig"),
                .product(name: "SwiftSpice", package: "spice-swift"),
            ],
            path: "Packages/SpiceController/Sources/SpiceController"
        ),
        // The SwiftUI application with a narrow AppKit/Metal display bridge.
        .executableTarget(
            name: "Maspice",
            dependencies: [
                "SpiceController",
                .product(name: "SpiceSessionLogic", package: "SpiceSessionLogic"),
                .product(name: "VVConfig", package: "VVConfig"),
                .product(name: "SwiftSpice", package: "spice-swift"),
            ],
            path: "Sources/Maspice"
        ),
        .testTarget(
            name: "MaspiceTests",
            dependencies: ["SpiceController"],
            path: "Tests/MaspiceTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
