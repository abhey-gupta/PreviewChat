// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PreviewChat",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "PreviewChat", path: "Sources/PreviewChat")
    ]
)
