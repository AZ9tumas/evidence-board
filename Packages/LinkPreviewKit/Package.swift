// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LinkPreviewKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LinkPreviewKit", targets: ["LinkPreviewKit"]),
    ],
    dependencies: [
        .package(path: "../BoardKit"),
    ],
    targets: [
        .target(name: "LinkPreviewKit", dependencies: ["BoardKit"]),
        .testTarget(name: "LinkPreviewKitTests", dependencies: ["LinkPreviewKit"]),
    ]
)
