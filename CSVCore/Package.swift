// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CSVCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [.library(name: "CSVCore", targets: ["CSVCore"])],
    targets: [
        .target(name: "CSVCore", resources: [.process("Resources")]),
        .testTarget(name: "CSVCoreTests", dependencies: ["CSVCore"])
    ]
)
