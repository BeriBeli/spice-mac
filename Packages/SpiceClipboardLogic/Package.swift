// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SpiceClipboardLogic",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "SpiceClipboardLogic", targets: ["SpiceClipboardLogic"]),
    ],
    targets: [
        .target(name: "SpiceClipboardLogic"),
        .testTarget(
            name: "SpiceClipboardLogicTests",
            dependencies: ["SpiceClipboardLogic"]
        ),
    ]
)
