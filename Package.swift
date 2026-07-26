// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OpenPane",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "OpenPane", targets: ["OpenPane"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.8.0"),
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter.git", exact: "0.10.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-bash.git", exact: "0.25.1"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-c.git", exact: "0.24.2"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-cpp.git", exact: "0.23.4"),
        // These releases explicitly compile their required external scanners.
        // Newer manifests use a cwd-sensitive FileManager check that SwiftPM 6
        // evaluates incorrectly when this package is a dependency.
        .package(url: "https://github.com/tree-sitter/tree-sitter-css.git", exact: "0.23.2"),
        .package(url: "https://github.com/camdencheek/tree-sitter-dockerfile.git", exact: "0.2.0"),
        .package(url: "https://github.com/the-mikedavis/tree-sitter-diff.git", exact: "0.1.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-go.git", exact: "0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-html.git", exact: "0.23.2"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-java.git", exact: "0.23.5"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-javascript.git", exact: "0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-json.git", exact: "0.24.8"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-kotlin.git", exact: "1.1.0"),
        .package(url: "https://github.com/MDeiml/tree-sitter-markdown.git", exact: "0.5.3"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-objc.git", exact: "3.0.2"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-python.git", exact: "0.23.6"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-rust.git", exact: "0.24.2"),
        .package(url: "https://github.com/takegue/tree-sitter-sql-bigquery.git", exact: "0.8.0"),
        .package(
            url: "https://github.com/alex-pinkus/tree-sitter-swift.git",
            revision: "31d17fe7e818a2048c808b5c6fdc2dc792f4f5b5"
        ),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-toml.git", exact: "0.7.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript.git", exact: "0.23.2"),
        .package(
            url: "https://github.com/mattmassicotte/tree-sitter-yaml.git",
            revision: "bd633dc67bd71934961610ca8bd832bf2153883e"
        ),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-xml.git", exact: "0.7.0")
    ],
    targets: [
        .target(
            name: "OpenPaneCore",
            path: "Sources/OpenPaneCore"
        ),
        .executableTarget(
            name: "OpenPane",
            dependencies: [
                "OpenPaneCore",
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterBash", package: "tree-sitter-bash"),
                .product(name: "TreeSitterC", package: "tree-sitter-c"),
                .product(name: "TreeSitterCPP", package: "tree-sitter-cpp"),
                .product(name: "TreeSitterCSS", package: "tree-sitter-css"),
                .product(name: "TreeSitterDockerfile", package: "tree-sitter-dockerfile"),
                .product(name: "TreeSitterDiff", package: "tree-sitter-diff"),
                .product(name: "TreeSitterGo", package: "tree-sitter-go"),
                .product(name: "TreeSitterHTML", package: "tree-sitter-html"),
                .product(name: "TreeSitterJava", package: "tree-sitter-java"),
                .product(name: "TreeSitterJavaScript", package: "tree-sitter-javascript"),
                .product(name: "TreeSitterJSON", package: "tree-sitter-json"),
                .product(name: "TreeSitterKotlin", package: "tree-sitter-kotlin"),
                .product(name: "TreeSitterMarkdown", package: "tree-sitter-markdown"),
                .product(name: "TreeSitterObjc", package: "tree-sitter-objc"),
                .product(name: "TreeSitterPython", package: "tree-sitter-python"),
                .product(name: "TreeSitterRust", package: "tree-sitter-rust"),
                .product(name: "TreeSitterSqlBigquery", package: "tree-sitter-sql-bigquery"),
                .product(name: "TreeSitterSwift", package: "tree-sitter-swift"),
                .product(name: "TreeSitterTOML", package: "tree-sitter-toml"),
                .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
                .product(name: "TreeSitterYAML", package: "tree-sitter-yaml"),
                .product(name: "TreeSitterXML", package: "tree-sitter-xml")
            ],
            path: "Sources/OpenPane"
        ),
        .testTarget(
            name: "OpenPaneCoreTests",
            dependencies: ["OpenPaneCore"],
            path: "Tests/OpenPaneCoreTests"
        ),
        .testTarget(
            name: "OpenPaneTests",
            dependencies: ["OpenPane", "OpenPaneCore"],
            path: "Tests/OpenPaneTests"
        )
    ]
)
