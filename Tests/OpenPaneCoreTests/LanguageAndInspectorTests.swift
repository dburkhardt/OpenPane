import Foundation
import Testing
@testable import OpenPaneCore

@Suite("Language registry")
struct LanguageRegistryTests {
    private let registry = LanguageRegistry.builtIn

    @Test("Manual language override has highest precedence")
    func manualOverride() {
        let result = registry.detect(
            filename: "script.py",
            contentPrefix: "#!/bin/bash",
            manualOverride: "swift"
        )
        #expect(result.id == "swift")
    }

    @Test("Exact filename precedes content sniffing")
    func exactFilename() {
        let result = registry.detect(
            filename: "Dockerfile",
            contentPrefix: #"{"looks":"json"}"#
        )
        #expect(result.id == "dockerfile")
    }

    @Test("Extension precedes shebang")
    func extensionBeforeShebang() {
        let result = registry.detect(
            filename: "tool.py",
            contentPrefix: "#!/bin/bash\nprint('hello')"
        )
        #expect(result.id == "python")
    }

    @Test("Shebang detects extensionless Python")
    func shebang() {
        let result = registry.detect(
            filename: "tool",
            contentPrefix: "#!/usr/bin/env python3\nprint('hello')"
        )
        #expect(result.id == "python")
    }

    @Test("Unknown content falls back to plain text")
    func plainTextFallback() {
        #expect(registry.detect(filename: "unknown", contentPrefix: "hello").id == "plaintext")
    }

    @Test("Bundled comment rules match the source language")
    func commentRules() {
        #expect(registry.definition(id: "python")?.lineComment == "#")
        #expect(
            registry.definition(id: "markdown")?.blockComment
                == BlockComment("<!--", "-->")
        )
        #expect(
            registry.definition(id: "css")?.blockComment
                == BlockComment("/*", "*/")
        )
        #expect(registry.definition(id: "json")?.lineComment == nil)
        #expect(registry.definition(id: "json")?.blockComment == nil)
    }
}

@Suite("Binary inspection")
struct BinaryInspectorTests {
    @Test("Raw rendering makes controls and invalid bytes visible")
    func rawRendering() {
        let rendered = BinaryTextRenderer.render(
            Data([0x41, 0x00, 0x09, 0x0A, 0xFF])
        )

        #expect(rendered == "A␀⇥↵\n‹FF›")
    }

    @Test("Hex rows have stable offsets, padding, and ASCII")
    func hexRows() throws {
        let rows = HexRenderer.rows(
            for: Data([0x41, 0x42, 0x00, 0xFF, 0x43]),
            bytesPerRow: 4
        )

        #expect(rows.count == 2)
        #expect(rows[0].formattedOffset == "00000000")
        #expect(rows[0].hexadecimal == "41 42 00 FF")
        #expect(rows[0].ascii == "AB··")
        #expect(rows[1].formattedOffset == "00000004")
        #expect(rows[1].hexadecimal == "43         ")
        #expect(rows[1].ascii == "C")
    }
}

@Suite("Hidden file policy")
struct HiddenFilePolicyTests {
    private let policy = HiddenFilePolicy()

    @Test("Useful dotfiles remain visible")
    func usefulDotfiles() {
        #expect(policy.shouldShow(name: ".env", isDirectory: false, showAllFiles: false))
        #expect(policy.shouldShow(name: ".github", isDirectory: true, showAllFiles: false))
    }

    @Test("Generated and VCS internals are hidden by default")
    func defaults() {
        #expect(!policy.shouldShow(name: ".DS_Store", isDirectory: false, showAllFiles: false))
        #expect(!policy.shouldShow(name: ".git", isDirectory: true, showAllFiles: false))
        #expect(!policy.shouldShow(name: "node_modules", isDirectory: true, showAllFiles: false))
        #expect(policy.shouldShow(name: ".DS_Store", isDirectory: false, showAllFiles: true))
    }

    @Test("Directory symlinks are never descended automatically")
    func symlinkDescent() throws {
        try withTemporaryDirectory { directory in
            let real = directory.appendingPathComponent("real", isDirectory: true)
            let link = directory.appendingPathComponent("link", isDirectory: true)
            try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

            #expect(!policy.shouldDescend(into: link))
            #expect(policy.shouldDescend(into: real))
        }
    }
}

private func withTemporaryDirectory(
    _ body: (URL) throws -> Void
) throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("OpenPaneCoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url) }
    try body(url)
}
