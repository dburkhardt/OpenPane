import Foundation
import Testing
@testable import OpenPaneCore

@Suite("Text codec")
struct TextCodecTests {
    @Test("A no-op UTF-8 CRLF round trip is byte-identical")
    func noOpRoundTrip() throws {
        let original = Data([0xEF, 0xBB, 0xBF]) + Data("first\r\nsecond\r\n".utf8)
        let decoded = try #require(TextCodec.decode(original))

        #expect(decoded.text == "first\nsecond\n")
        #expect(decoded.metadata.encoding == .utf8)
        #expect(decoded.metadata.byteOrderMark == .utf8)
        #expect(decoded.metadata.lineEndings == .crlf)
        #expect(decoded.metadata.hasTrailingNewline)

        let encoded = try TextCodec.encode(decoded.text, preserving: decoded)
        #expect(encoded == original)
    }

    @Test("Edited text retains the original encoding, BOM, and line endings")
    func preservesFormatAfterEdit() throws {
        var original = ByteOrderMark.utf16LittleEndian.bytes
        original.append(
            try #require("one\r\ntwo".data(using: .utf16LittleEndian))
        )
        let decoded = try #require(TextCodec.decode(original))
        let encoded = try TextCodec.encode(
            "one\ntwo\nthree",
            metadata: decoded.metadata,
            originalText: decoded.originalText,
            originalData: decoded.originalData
        )

        #expect(encoded.starts(with: ByteOrderMark.utf16LittleEndian.bytes))
        let payload = Data(encoded.dropFirst(ByteOrderMark.utf16LittleEndian.bytes.count))
        #expect(String(data: payload, encoding: .utf16LittleEndian) == "one\r\ntwo\r\nthree")
    }

    @Test("Mixed line endings are identified without changing no-op bytes")
    func mixedLineEndings() throws {
        let original = Data("a\r\nb\nc\rd".utf8)
        let decoded = try #require(TextCodec.decode(original))

        #expect(decoded.metadata.lineEndings == .mixed)
        #expect(decoded.metadata.originalLineEndings == [.crlf, .lf, .cr])
        #expect(decoded.text == "a\nb\nc\nd")
        #expect(try TextCodec.encode(decoded.text, preserving: decoded) == original)
    }

    @Test("An edited mixed-line-ending file keeps its separator pattern")
    func preservesMixedLineEndingsAfterEdit() throws {
        let original = Data("a\r\nb\nc\rd".utf8)
        let decoded = try #require(TextCodec.decode(original))

        let encoded = try TextCodec.encode(
            "A\nb\nc\nd",
            metadata: decoded.metadata,
            originalText: decoded.originalText,
            originalData: decoded.originalData
        )

        #expect(encoded == Data("A\r\nb\nc\rd".utf8))
    }

    @Test("New lines in a mixed file use its dominant original separator")
    func mixedLineEndingFallback() throws {
        let original = Data("a\r\nb\r\nc\nd".utf8)
        let decoded = try #require(TextCodec.decode(original))

        let encoded = try TextCodec.encode(
            "a\nb\nc\nd\ne",
            metadata: decoded.metadata,
            originalText: decoded.originalText,
            originalData: decoded.originalData
        )

        #expect(encoded == Data("a\r\nb\r\nc\nd\r\ne".utf8))
    }

    @Test("Lossless common legacy text is detected")
    func legacyEncoding() throws {
        let original = try #require("Résumé".data(using: .windowsCP1252))
        let decoded = try #require(TextCodec.decode(original))

        #expect(decoded.text == "Résumé")
        #expect(decoded.metadata.encoding == .windows1252)
        #expect(try TextCodec.encode(decoded.text, preserving: decoded) == original)
    }

    @Test("BOM-marked UTF-16 and UTF-32 remain byte-identical")
    func unicodeBOMRoundTrips() throws {
        let cases: [(TextEncoding, ByteOrderMark)] = [
            (.utf16LittleEndian, .utf16LittleEndian),
            (.utf16BigEndian, .utf16BigEndian),
            (.utf32LittleEndian, .utf32LittleEndian),
            (.utf32BigEndian, .utf32BigEndian),
        ]

        for (encoding, bom) in cases {
            let payload = try #require(
                "café 🚀\r\n".data(using: encoding.foundationEncoding)
            )
            let original = bom.bytes + payload
            let decoded = try #require(TextCodec.decode(original))

            #expect(decoded.metadata.encoding == encoding)
            #expect(decoded.metadata.byteOrderMark == bom)
            #expect(try TextCodec.encode(decoded.text, preserving: decoded) == original)
        }
    }

    @Test("NUL-heavy bytes are not accepted as text")
    func rejectsBinary() {
        let data = Data([0x00, 0x01, 0x02, 0x03, 0x00, 0xFF])
        #expect(TextCodec.decode(data) == nil)
    }

    @Test("A leading BOM scalar in the document is not mistaken for file metadata")
    func preservesLeadingBOMScalar() throws {
        let metadata = TextFileMetadata(encoding: .utf8)
        let encoded = try TextCodec.encode("\u{FEFF}content", metadata: metadata)

        #expect(encoded == Data("\u{FEFF}content".utf8))
        #expect(!encoded.starts(with: ByteOrderMark.utf8.bytes + ByteOrderMark.utf8.bytes))
    }

    @Test(
        "Line-ending detection",
        arguments: [
            ("", LineEndingConvention.none),
            ("a\n", .lf),
            ("a\r\n", .crlf),
            ("a\r", .cr),
            ("a\r\nb\n", .mixed),
        ]
    )
    func detectsLineEndings(text: String, expected: LineEndingConvention) {
        #expect(TextCodec.lineEndingConvention(in: text) == expected)
    }
}
