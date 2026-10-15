// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CSVCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "CSVCore", targets: ["CSVCore"])],
    targets: [
        .target(name: "CSVCore"),
        .testTarget(name: "CSVCoreTests", dependencies: ["CSVCore"])
    ]
)
