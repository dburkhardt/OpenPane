import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var markdownDocument: UTType {
        UTType(filenameExtension: "md") ?? .plainText
    }
}

struct MarkdownDocument: FileDocument {
    static let readableContentTypes: [UTType] = [
        .markdownDocument,
        .plainText
    ]

    var text: String

    init(text: String = MarkdownDocument.welcomeText) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let value = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = value
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return FileWrapper(regularFileWithContents: data)
    }

    static let welcomeText = """
    # Welcome to OpenPane

    A free, native Markdown reader and editor for macOS.

    ## The first working slice

    - [x] Native document opening and saving
    - [x] Source, preview, and split modes
    - [x] Outline navigation
    - [x] Local proofreading checks
    - [x] HTML export
    - [ ] Full GFM table rendering
    - [ ] Mermaid and LaTeX
    - [ ] Quick Look extension
    - [ ] PDF, DOCX, and EPUB publishing

    > OpenPane is a clean-room feature-parity project. It does not copy the
    > branding, interface, or proprietary code of another application.

    ```swift
    struct Markdown: Sendable {
        let source: String
    }
    ```
    """
}
