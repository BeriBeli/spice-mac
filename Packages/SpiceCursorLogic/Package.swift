// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SpiceCursorLogic",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "SpiceCursorLogic", targets: ["SpiceCursorLogic"]),
    ],
    targets: [
        .target(name: "SpiceCursorLogic"),
        .testTarget(
            name: "SpiceCursorLogicTests",
            dependencies: ["SpiceCursorLogic"]
        ),
    ]
)
