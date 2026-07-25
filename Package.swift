// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OpenPane",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "OpenPane", targets: ["OpenPane"])
    ],
    targets: [
        .executableTarget(
            name: "OpenPane",
            path: "Sources/OpenPane"
        ),
        .testTarget(
            name: "OpenPaneTests",
            dependencies: ["OpenPane"],
            path: "Tests/OpenPaneTests"
        )
    ]
)
