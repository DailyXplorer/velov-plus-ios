// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "VelovCore",
    defaultLocalization: "fr",
    platforms: [.iOS("18.0"), .macOS(.v14)],
    products: [.library(name: "VelovCore", targets: ["VelovCore"])],
    targets: [
        .target(name: "VelovCore", swiftSettings: [.enableUpcomingFeature("BareSlashRegexLiterals")]),
        .testTarget(name: "VelovCoreTests", dependencies: ["VelovCore"], swiftSettings: [.enableUpcomingFeature("BareSlashRegexLiterals")])
    ]
)
