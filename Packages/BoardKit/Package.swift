// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BoardKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BoardKit", targets: ["BoardKit"]),
    ],
    targets: [
        .target(name: "BoardKit"),
        .testTarget(name: "BoardKitTests", dependencies: ["BoardKit"]),
    ]
)
