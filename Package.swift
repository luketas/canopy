// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Canopy",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CanopyCore", targets: ["CanopyCore"]),
        .executable(name: "Canopy", targets: ["Canopy"]),
        .executable(name: "CanopyFixture",targets: ["CanopyFixture"])
    ],
    targets: [
        .target(name: "CanopyCore"),
        .executableTarget(name: "Canopy", dependencies: ["CanopyCore"]),
        .executableTarget(name: "CanopyFixture"),
        .testTarget(name: "CanopyCoreTests", dependencies: ["CanopyCore"]),
        .testTarget(name: "CanopyTests", dependencies: ["Canopy", "CanopyCore"])
    ],
    swiftLanguageModes: [.v5]
)
