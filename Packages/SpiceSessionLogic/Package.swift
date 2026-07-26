// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "SpiceSessionLogic",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SpiceSessionLogic", targets: ["SpiceSessionLogic"]),
    ],
    targets: [
        .target(name: "SpiceSessionLogic"),
        .testTarget(
            name: "SpiceSessionLogicTests",
            dependencies: ["SpiceSessionLogic"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
