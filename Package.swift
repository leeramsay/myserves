// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "myserves",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "myserves",
            path: "Sources/myserves"
        )
    ]
)
