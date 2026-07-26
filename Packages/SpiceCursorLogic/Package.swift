// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "SpiceCursorLogic",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SpiceCursorLogic", targets: ["SpiceCursorLogic"]),
    ],
    targets: [
        .target(name: "SpiceCursorLogic"),
        .testTarget(
            name: "SpiceCursorLogicTests",
            dependencies: ["SpiceCursorLogic"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
