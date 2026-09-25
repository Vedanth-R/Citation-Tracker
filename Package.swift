// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "CiteKit", platforms: [.macOS(.v14)], products: [
    .library(name: "CiteKitCore", targets: ["CiteKitCore"]),
    .executable(name: "CiteKit", targets: ["CiteKitApp"])
], targets: [
    .target(name: "CiteKitCore", resources: [.process("Resources")]),
    .executableTarget(name: "CiteKitApp", dependencies: ["CiteKitCore"]),
    .testTarget(name: "CiteKitCoreTests", dependencies: ["CiteKitCore"]),
    .testTarget(name: "CiteKitAppTests", dependencies: ["CiteKitApp"])
], swiftLanguageModes: [.v5])
