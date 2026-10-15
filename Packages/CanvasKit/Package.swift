// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CanvasKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CanvasKit", targets: ["CanvasKit"]),
    ],
    dependencies: [
        .package(path: "../BoardKit"),
        .package(path: "../LinkPreviewKit"),
    ],
    targets: [
        .target(name: "CanvasKit", dependencies: ["BoardKit", "LinkPreviewKit"]),
        .testTarget(name: "CanvasKitTests", dependencies: ["CanvasKit"]),
    ]
)
