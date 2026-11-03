// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CopyTaste",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CopyTasteCore", targets: ["CopyTasteCore"]),
        .executable(name: "CopyTaste", targets: ["CopyTaste"])
    ],
    targets: [
        .target(name: "CopyTasteCore"),
        .executableTarget(name: "CopyTaste", dependencies: ["CopyTasteCore"]),
        .testTarget(name: "CopyTasteCoreTests", dependencies: ["CopyTasteCore", "CopyTaste"])
    ]
)
