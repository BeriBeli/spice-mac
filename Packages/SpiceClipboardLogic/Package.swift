// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "SpiceClipboardLogic",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SpiceClipboardLogic", targets: ["SpiceClipboardLogic"]),
    ],
    targets: [
        .target(name: "SpiceClipboardLogic"),
        .testTarget(
            name: "SpiceClipboardLogicTests",
            dependencies: ["SpiceClipboardLogic"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
