import Foundation
import Testing
@testable import OpenPane

@Suite("Syntax highlighting coordinates")
@MainActor
struct SyntaxHighlightingTests {
    @Test("UTF-16 ranges round-trip through UTF-16LE bytes")
    func coordinateRoundTrip() {
        let source = "ASCII café 🚀"
        let range = (source as NSString).range(of: "café 🚀")

        let bytes = TreeSitterUTF16LECoordinates.byteRange(fromUTF16: range)

        #expect(bytes != nil)
        #expect(
            bytes.flatMap(TreeSitterUTF16LECoordinates.utf16Range(fromBytes:))
                == range
        )
    }

    @Test("Odd byte offsets are rejected")
    func rejectsHalfCodeUnit() {
        #expect(
            TreeSitterUTF16LECoordinates.utf16Range(fromBytes: 1..<4) == nil
        )
    }

    @Test("Visible ranges expand away from an emoji surrogate boundary")
    func visibleRangeSurrogateBoundary() {
        let source = String(repeating: "a", count: 64) + "🚀"
            + String(repeating: "b", count: 64)
        let emojiRange = (source as NSString).range(of: "🚀")
        let lowSurrogateOnly = NSRange(
            location: emojiRange.location + 1,
            length: 1
        )

        let bounded = TreeSitterUTF16LECoordinates.boundedVisibleRange(
            lowSurrogateOnly,
            in: source,
            threshold: 1,
            padding: 0
        )

        #expect(bounded == emojiRange)
        let expectedBytes = UInt32(emojiRange.location * 2)..<UInt32(NSMaxRange(emojiRange) * 2)
        #expect(
            bounded.flatMap(TreeSitterUTF16LECoordinates.byteRange(fromUTF16:))
                == expectedBytes
        )
    }

    @Test("Captures remain aligned after accents and emoji")
    func capturesUseAppKitRanges() {
        let source = #"{"café":"🚀","count":2}"#
        let highlighter = IncrementalSyntaxHighlighter()
        highlighter.setLanguage("json")

        let spans = highlighter.highlights(in: source)
        let sourceLength = source.utf16.count
        let stringRanges = [
            (source as NSString).range(of: #""café""#),
            (source as NSString).range(of: #""🚀""#)
        ]

        #expect(!spans.isEmpty)
        #expect(spans.allSatisfy { NSMaxRange($0.range) <= sourceLength })
        for expected in stringRanges {
            #expect(
                spans.contains {
                    $0.role == .string && $0.range == expected
                }
            )
        }
    }

    @Test("Emoji replacement incrementally matches a clean parse")
    func emojiIncrementalEdit() {
        let oldSource = #"let value = "😀""#
        let newSource = #"let value = "😁""#
        let incremental = IncrementalSyntaxHighlighter()
        incremental.setLanguage("swift")
        _ = incremental.highlights(in: oldSource)

        let edited = incremental.highlights(in: newSource)

        let clean = IncrementalSyntaxHighlighter()
        clean.setLanguage("swift")
        #expect(edited == clean.highlights(in: newSource))
        #expect(!edited.isEmpty)
        #expect(
            edited.allSatisfy {
                NSMaxRange($0.range) <= newSource.utf16.count
            }
        )
    }

    @Test("Explicit edit after an accented identifier remains aligned")
    func explicitEditAfterAccent() {
        let oldSource = "let café = 1"
        let newSource = "let café = 42"
        let replacementRange = (oldSource as NSString).range(of: "1")
        let highlighter = IncrementalSyntaxHighlighter()
        highlighter.setLanguage("swift")
        _ = highlighter.highlights(in: oldSource)

        let spans = highlighter.highlights(
            in: newSource,
            edit: .init(range: replacementRange, replacement: "42")
        )

        let expected = (newSource as NSString).range(of: "42")
        #expect(
            spans.contains {
                $0.role == .number && $0.range == expected
            }
        )
    }

    @Test(
        "The complete language pack uses bundled grammars",
        arguments: [
            ("xml", "<item enabled=\"true\">value</item>"),
            ("kotlin", "data class Item(val value: Int)"),
            ("objective-c", "@interface Item : NSObject\n@end"),
        ]
    )
    func completeLanguagePack(languageID: String, source: String) {
        let highlighter = IncrementalSyntaxHighlighter()
        highlighter.setLanguage(languageID)

        #expect(highlighter.hasActiveGrammar)
        #expect(!highlighter.highlights(in: source).isEmpty)
    }

    @Test("A 20,000-character JSON line highlights within valid ranges")
    func longJSONLine() {
        let source = #"{"payload":""#
            + String(repeating: "a", count: 20_000)
            + #""}"#
        let highlighter = IncrementalSyntaxHighlighter()
        highlighter.setLanguage("json")

        let spans = highlighter.highlights(
            in: source,
            visibleRange: NSRange(location: 0, length: 512)
        )
        let length = (source as NSString).length

        #expect(!spans.isEmpty)
        #expect(
            spans.allSatisfy {
                $0.range.location >= 0
                    && $0.range.length >= 0
                    && NSMaxRange($0.range) <= length
            }
        )
    }
}
