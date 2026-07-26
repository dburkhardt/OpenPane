import Foundation
import Testing
@testable import OpenPaneCore

@Suite("File classification")
struct FileClassifierTests {
    private let classifier = FileClassifier()

    @Test("PDF magic wins when the extension is unrelated")
    func renamedPDF() {
        let data = Data("leading bytes\n%PDF-1.7\n".utf8)
        let result = classifier.classify(data: data, filename: "report.download")

        #expect(result.kind == .pdf)
        #expect(result.availableViewModes == [.pdf])
        #expect(!result.isEditable)
    }

    @Test("A binary payload with a Markdown extension stays binary")
    func binaryMarkdown() {
        let result = classifier.classify(
            data: Data([0x00, 0x01, 0x02, 0xFF]),
            filename: "README.md"
        )

        #expect(result.kind == .binary)
        #expect(result.availableViewModes == [.rawText, .hex])
        #expect(!result.isEditable)
    }

    @Test("Markdown opens in its reader")
    func markdownReader() {
        let result = classifier.classify(
            data: Data("# Hello\n".utf8),
            filename: "notes.md"
        )

        #expect(result.kind == .markdown)
        #expect(result.defaultViewMode == .reader)
        #expect(result.isEditable)
    }

    @Test("JSON is exact source text with a JSON language ID")
    func jsonSource() {
        let result = classifier.classify(
            data: Data(#"{"value":1}"#.utf8),
            filename: "sample.json"
        )

        #expect(result.kind == .text(languageID: "json"))
        #expect(result.defaultViewMode == .source)
    }

    @Test("Recognized images route to the system preview")
    func systemPreview() {
        let result = classifier.classify(
            data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]),
            filename: "image.png"
        )

        guard case .systemPreview = result.kind else {
            Issue.record("Expected system preview, got \(result.kind)")
            return
        }
        #expect(result.availableViewModes == [.systemPreview])
    }

    @Test("Large text is source-only and non-editable")
    func largeText() {
        let result = classifier.classify(
            data: Data("hello".utf8),
            filename: "large.txt",
            totalByteCount: 21 * 1_024 * 1_024
        )

        #expect(result.isLargeFile)
        #expect(!result.isEditable)
        #expect(result.availableViewModes == [.source])
    }

    @Test("The 20 MiB editing boundary is exact")
    func editingBoundary() {
        let limit = UInt64(20 * 1_024 * 1_024)
        let prefix = Data("print('bounded')\n".utf8)

        let atLimit = classifier.classify(
            data: prefix,
            filename: "script.py",
            totalByteCount: limit
        )
        let beyondLimit = classifier.classify(
            data: prefix,
            filename: "script.py",
            totalByteCount: limit + 1
        )

        #expect(!atLimit.isLargeFile)
        #expect(atLimit.isEditable)
        #expect(beyondLimit.isLargeFile)
        #expect(!beyondLimit.isEditable)
    }

    @Test("Malformed byte prefixes always produce a bounded viewer choice")
    func hostileBytePrefixes() {
        for length in 0...256 {
            let bytes = (0..<length).map {
                UInt8(truncatingIfNeeded: ($0 * 73) ^ (length * 29))
            }
            let result = classifier.classify(
                data: Data(bytes),
                filename: "hostile-\(length).data"
            )

            #expect(!result.availableViewModes.isEmpty)
            if case .binary = result.kind {
                #expect(!result.isEditable)
            }
        }
    }
}
