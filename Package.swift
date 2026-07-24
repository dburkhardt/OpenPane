// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "FreeMark",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FreeMark", targets: ["FreeMark"])
    ],
    targets: [
        .executableTarget(
            name: "FreeMark",
            path: "Sources/FreeMark"
        ),
        .testTarget(
            name: "FreeMarkTests",
            dependencies: ["FreeMark"],
            path: "Tests/FreeMarkTests"
        )
    ]
)
