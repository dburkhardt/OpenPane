import Foundation
import Testing
@testable import OpenPane
import OpenPaneCore

@Suite("Comment toggling")
struct CommentToggleTests {
    private let registry = LanguageRegistry.builtIn

    @Test("A block-only language preserves a selected line ending")
    func blockCommentPreservesLineEnding() throws {
        let definition = try #require(registry.definition(id: "markdown"))
        let source = "first\nsecond"
        let first = try #require(
            CommentToggleTransformer.edit(
                in: source,
                selection: NSRange(location: 2, length: 0),
                definition: definition
            )
        )

        #expect(applying(first, to: source) == "<!-- first -->\nsecond")
        #expect(first.selection.length == 0)

        let commented = applying(first, to: source)
        let second = try #require(
            CommentToggleTransformer.edit(
                in: commented,
                selection: first.selection,
                definition: definition
            )
        )
        #expect(applying(second, to: commented) == source)
    }

    @Test("Multiline block comments round-trip without wrapper whitespace")
    func multilineBlockCommentRoundTrip() throws {
        let definition = try #require(registry.definition(id: "css"))
        let source = "foo\nbar"
        let first = try #require(
            CommentToggleTransformer.edit(
                in: source,
                selection: NSRange(location: 0, length: source.utf16.count),
                definition: definition
            )
        )
        let commented = applying(first, to: source)

        #expect(commented == "/*\nfoo\nbar\n*/")

        let second = try #require(
            CommentToggleTransformer.edit(
                in: commented,
                selection: first.selection,
                definition: definition
            )
        )
        #expect(applying(second, to: commented) == source)
    }

    @Test("Line comments retain a usable selection and round-trip")
    func lineCommentSelectionRoundTrip() throws {
        let definition = try #require(registry.definition(id: "python"))
        let source = "first\nsecond\n"
        let selection = NSRange(location: 0, length: "first\nsecond".utf16.count)
        let first = try #require(
            CommentToggleTransformer.edit(
                in: source,
                selection: selection,
                definition: definition
            )
        )
        let commented = applying(first, to: source)

        #expect(commented == "# first\n# second\n")
        #expect(first.selection == NSRange(location: 0, length: 17))

        let second = try #require(
            CommentToggleTransformer.edit(
                in: commented,
                selection: first.selection,
                definition: definition
            )
        )
        #expect(applying(second, to: commented) == source)
    }

    @Test("JSX and TSX do not emit context-invalid comment markers")
    func mixedSyntaxCommentsDisabled() {
        for filename in ["Component.jsx", "Component.tsx"] {
            let detected = registry.detect(
                filename: filename,
                contentPrefix: "const element = <div />"
            )
            #expect(detected.id == (filename.hasSuffix(".jsx") ? "jsx" : "tsx"))
            #expect(detected.lineComment == nil)
            #expect(detected.blockComment == nil)
        }
    }

    @Test("Invalid editor ranges are rejected")
    func invalidRanges() throws {
        let definition = try #require(registry.definition(id: "python"))
        #expect(
            CommentToggleTransformer.edit(
                in: "text",
                selection: NSRange(location: -1, length: 0),
                definition: definition
            ) == nil
        )
        #expect(
            CommentToggleTransformer.edit(
                in: "text",
                selection: NSRange(location: 0, length: -1),
                definition: definition
            ) == nil
        )
    }

    private func applying(
        _ edit: CommentToggleEdit,
        to source: String
    ) -> String {
        (source as NSString).replacingCharacters(
            in: edit.range,
            with: edit.replacement
        )
    }
}
