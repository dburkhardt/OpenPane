import Darwin
import Foundation
import Testing
@testable import OpenPaneCore

@Suite("File I/O", .serialized)
struct FileIOActorTests {
    @Test("A no-op coordinated save preserves exact bytes and permissions")
    func noOpSave() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("sample.txt")
            let original = Data([0xEF, 0xBB, 0xBF]) + Data("first\r\nsecond\r\n".utf8)
            try original.write(to: url)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: UInt16(0o744))],
                ofItemAtPath: url.path
            )

            let fileIO = FileIOActor()
            let loaded = try await fileIO.load(url: url)
            let decoded = try #require(loaded.decodedText)
            let receipt = try await fileIO.save(
                text: decoded.text,
                decodedText: decoded,
                to: url,
                expectedFingerprint: loaded.fingerprint
            )

            #expect(try Data(contentsOf: url) == original)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.uint16Value == 0o744)
            #expect(receipt.fingerprint.contentSHA256 == FileFingerprint.forData(original).contentSHA256)
        }
    }

    @Test("An edited save preserves user extended attributes")
    func preservesExtendedAttributes() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("metadata.txt")
            try Data("before".utf8).write(to: url)
            let attributeName = "com.openpane.fixture"
            let attributeValue = Data("preserve-me".utf8)
            let setResult = attributeValue.withUnsafeBytes { bytes in
                url.path.withCString { path in
                    attributeName.withCString { name in
                        setxattr(
                            path,
                            name,
                            bytes.baseAddress,
                            bytes.count,
                            0,
                            0
                        )
                    }
                }
            }
            try #require(setResult == 0)

            let fileIO = FileIOActor()
            let loaded = try await fileIO.load(url: url)
            let decoded = try #require(loaded.decodedText)
            _ = try await fileIO.save(
                text: "after",
                decodedText: decoded,
                to: url,
                expectedFingerprint: loaded.fingerprint
            )

            let valueLength = url.path.withCString { path in
                attributeName.withCString { name in
                    getxattr(path, name, nil, 0, 0, 0)
                }
            }
            try #require(valueLength == attributeValue.count)
            var preserved = Data(count: valueLength)
            let readResult = preserved.withUnsafeMutableBytes { bytes in
                url.path.withCString { path in
                    attributeName.withCString { name in
                        getxattr(
                            path,
                            name,
                            bytes.baseAddress,
                            bytes.count,
                            0,
                            0
                        )
                    }
                }
            }
            #expect(readResult == attributeValue.count)
            #expect(preserved == attributeValue)
        }
    }

    @Test("An external edit blocks a normal save")
    func externalConflict() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("sample.json")
            try Data(#"{"value":1}"#.utf8).write(to: url)
            let fileIO = FileIOActor()
            let loaded = try await fileIO.load(url: url)
            let decoded = try #require(loaded.decodedText)

            try Data(#"{"outside":true}"#.utf8).write(to: url)

            do {
                _ = try await fileIO.save(
                    text: #"{"value":2}"#,
                    decodedText: decoded,
                    to: url,
                    expectedFingerprint: loaded.fingerprint
                )
                Issue.record("Expected an external-modification error")
            } catch let error as FileIOError {
                guard case .externalModification = error else {
                    Issue.record("Unexpected FileIOError: \(error)")
                    return
                }
            }
            #expect(try String(contentsOf: url, encoding: .utf8) == #"{"outside":true}"#)
        }
    }

    @Test("Explicit overwrite resolves a conflict")
    func overwriteConflict() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("sample.txt")
            try Data("before".utf8).write(to: url)
            let fileIO = FileIOActor()
            let loaded = try await fileIO.load(url: url)
            let decoded = try #require(loaded.decodedText)
            try Data("outside".utf8).write(to: url)

            _ = try await fileIO.save(
                text: "inside",
                decodedText: decoded,
                to: url,
                expectedFingerprint: loaded.fingerprint,
                overwriteExternalChanges: true
            )
            #expect(try String(contentsOf: url, encoding: .utf8) == "inside")
        }
    }

    @Test("Saving through a symlink leaves the link intact")
    func symlinkSave() async throws {
        try await withTemporaryDirectory { directory in
            let target = directory.appendingPathComponent("target.txt")
            let link = directory.appendingPathComponent("link.txt")
            try Data("before".utf8).write(to: target)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

            let fileIO = FileIOActor()
            let loaded = try await fileIO.load(url: link)
            let decoded = try #require(loaded.decodedText)
            _ = try await fileIO.save(
                text: "after",
                decodedText: decoded,
                to: link,
                expectedFingerprint: loaded.fingerprint
            )

            let values = try link.resourceValues(forKeys: [.isSymbolicLinkKey])
            #expect(values.isSymbolicLink == true)
            #expect(try String(contentsOf: target, encoding: .utf8) == "after")
        }
    }

    @Test("Large files use a bounded, read-only load")
    func boundedLargeFile() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("large.py")
            try Data(repeating: 0x61, count: 1_024).write(to: url)
            let fileIO = FileIOActor(
                configuration: FileIOConfiguration(
                    editableByteLimit: 128,
                    boundedInspectionByteLimit: 64,
                    sampledFingerprintByteCount: 16
                )
            )
            let loaded = try await fileIO.load(url: url)

            #expect(loaded.isBounded)
            #expect(loaded.data.count == 64)
            #expect(loaded.totalByteCount == 1_024)
            #expect(!loaded.classification.isEditable)
            #expect(loaded.fingerprint.coverage == .sampled)
        }
    }

    @Test("Recovery snapshots never write over the source")
    func recoverySnapshot() async throws {
        try await withTemporaryDirectory { directory in
            let source = directory.appendingPathComponent("source.txt")
            let recovery = directory.appendingPathComponent("Recovery", isDirectory: true)
            try Data("source".utf8).write(to: source)
            let fileIO = FileIOActor(
                configuration: FileIOConfiguration(recoveryDirectory: recovery)
            )
            let id = UUID()

            let snapshot = try await fileIO.writeRecoverySnapshot(
                sessionID: id,
                sourceURL: source,
                text: "unsaved"
            )

            #expect(snapshot.deletingLastPathComponent() == recovery)
            #expect(try String(contentsOf: source, encoding: .utf8) == "source")
            #expect(try String(contentsOf: snapshot, encoding: .utf8).contains("unsaved"))
            try await fileIO.removeRecoverySnapshot(sessionID: id)
            #expect(!FileManager.default.fileExists(atPath: snapshot.path))
        }
    }

    @Test("A binary text copy cannot overwrite its original")
    func binaryTextCopySafety() async throws {
        try await withTemporaryDirectory { directory in
            let source = directory.appendingPathComponent("source.bin")
            let copy = directory.appendingPathComponent("source.txt")
            let bytes = Data([0x00, 0x01, 0xFF])
            try bytes.write(to: source)
            let fileIO = FileIOActor()

            do {
                _ = try await fileIO.saveTextCopy(
                    "␀␁‹FF›",
                    to: source,
                    refusingOriginal: source
                )
                Issue.record("Expected binary overwrite refusal")
            } catch let error as FileIOError {
                guard case .binaryOverwriteRefused = error else {
                    Issue.record("Unexpected FileIOError: \(error)")
                    return
                }
            }
            #expect(try Data(contentsOf: source) == bytes)

            _ = try await fileIO.saveTextCopy(
                "␀␁‹FF›",
                to: copy,
                refusingOriginal: source
            )
            #expect(try String(contentsOf: copy, encoding: .utf8) == "␀␁‹FF›")
        }
    }
}

private func withTemporaryDirectory(
    _ body: (URL) async throws -> Void
) async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("OpenPaneFileIOTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url) }
    try await body(url)
}
