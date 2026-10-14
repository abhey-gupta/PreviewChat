// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PreviewChat",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/mgriebling/SwiftMath.git", from: "1.4.0")
    ],
    targets: [
        .executableTarget(
            name: "PreviewChat",
            dependencies: ["SwiftMath"],
            path: "Sources/PreviewChat"
        )
    ]
)
