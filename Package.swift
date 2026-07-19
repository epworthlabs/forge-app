// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ForgeCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "ForgeCore", targets: ["ForgeCore"])
    ],
    targets: [
        .target(name: "ForgeCore", resources: [.process("Resources")]),
        .testTarget(name: "ForgeCoreTests", dependencies: ["ForgeCore"])
    ]
)
