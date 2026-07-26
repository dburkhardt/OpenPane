import Foundation
import UniformTypeIdentifiers

public struct FileClassifier: Sendable {
    public struct Configuration: Sendable {
        public var editableByteLimit: UInt64
        public var languageRegistry: LanguageRegistry

        public init(
            editableByteLimit: UInt64 = 20 * 1_024 * 1_024,
            languageRegistry: LanguageRegistry = .builtIn
        ) {
            self.editableByteLimit = editableByteLimit
            self.languageRegistry = languageRegistry
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    public func classify(
        data: Data,
        filename: String,
        declaredContentTypeIdentifier: String? = nil,
        totalByteCount: UInt64? = nil
    ) -> FileClassification {
        let byteCount = totalByteCount ?? UInt64(data.count)
        let isLarge = byteCount > configuration.editableByteLimit
        let pathExtension = URL(fileURLWithPath: filename).pathExtension.lowercased()
        let declaredType = declaredContentTypeIdentifier.flatMap(UTType.init)
        let inferredType = UTType(filenameExtension: pathExtension)
        let contentType = declaredType ?? inferredType

        if isPDF(data: data, pathExtension: pathExtension, contentType: contentType) {
            return FileClassification(
                kind: .pdf,
                detectedTypeIdentifier: contentType?.identifier ?? UTType.pdf.identifier,
                totalByteCount: byteCount,
                isLargeFile: isLarge
            )
        }

        let language = configuration.languageRegistry.detect(
            filename: filename,
            contentPrefix: contentPrefix(from: data)
        )
        let isMarkdown = language.id == "markdown"
        let knownTextType = contentType?.conforms(to: .text) == true
            || contentType?.conforms(to: .sourceCode) == true
        let knownTextFilename = configuration.languageRegistry.isKnownTextFilename(filename)

        if isMarkdown || knownTextType || knownTextFilename {
            guard decodesAsText(data, isBoundedPrefix: UInt64(data.count) < byteCount) else {
                return binaryClassification(
                    contentType: contentType,
                    byteCount: byteCount,
                    isLarge: isLarge
                )
            }
            return FileClassification(
                kind: isMarkdown ? .markdown : .text(languageID: language.id),
                detectedTypeIdentifier: contentType?.identifier,
                totalByteCount: byteCount,
                isLargeFile: isLarge
            )
        }

        if isSystemPreviewType(contentType, pathExtension: pathExtension) {
            return FileClassification(
                kind: .systemPreview(contentTypeIdentifier: contentType?.identifier),
                detectedTypeIdentifier: contentType?.identifier,
                totalByteCount: byteCount,
                isLargeFile: isLarge
            )
        }

        if decodesAsText(data, isBoundedPrefix: UInt64(data.count) < byteCount) {
            return FileClassification(
                kind: .text(languageID: language.id),
                detectedTypeIdentifier: contentType?.identifier,
                totalByteCount: byteCount,
                isLargeFile: isLarge
            )
        }

        return binaryClassification(
            contentType: contentType,
            byteCount: byteCount,
            isLarge: isLarge
        )
    }

    public func classify(
        url: URL,
        data: Data,
        totalByteCount: UInt64? = nil
    ) -> FileClassification {
        let typeIdentifier = (try? url.resourceValues(forKeys: [.contentTypeKey]))?
            .contentType?
            .identifier
        return classify(
            data: data,
            filename: url.lastPathComponent,
            declaredContentTypeIdentifier: typeIdentifier,
            totalByteCount: totalByteCount
        )
    }

    private func isPDF(
        data: Data,
        pathExtension: String,
        contentType: UTType?
    ) -> Bool {
        let prefix = data.prefix(1_024)
        let signature = Data("%PDF-".utf8)
        return prefix.range(of: signature) != nil
            || pathExtension == "pdf"
            || contentType?.conforms(to: .pdf) == true
    }

    private func decodesAsText(_ data: Data, isBoundedPrefix: Bool) -> Bool {
        if TextCodec.decode(data) != nil { return true }
        guard isBoundedPrefix else { return false }

        // A bounded read can end in the middle of a UTF-8 scalar. Removing at
        // most three trailing bytes distinguishes that from invalid content.
        for count in 1...min(3, data.count) {
            if TextCodec.decode(Data(data.dropLast(count))) != nil {
                return true
            }
        }
        return false
    }

    private func contentPrefix(from data: Data) -> String {
        let limit = min(data.count, 16_384)
        let prefix = Data(data.prefix(limit))
        if let decoded = TextCodec.decode(prefix) {
            return decoded.text
        }
        return String(decoding: prefix, as: UTF8.self)
    }

    private func isSystemPreviewType(_ contentType: UTType?, pathExtension: String) -> Bool {
        if let contentType {
            if contentType.conforms(to: .image)
                || contentType.conforms(to: .audio)
                || contentType.conforms(to: .movie)
                || contentType.conforms(to: .audiovisualContent)
                || contentType.conforms(to: .archive)
            {
                return true
            }
        }

        return Self.systemPreviewExtensions.contains(pathExtension)
    }

    private func binaryClassification(
        contentType: UTType?,
        byteCount: UInt64,
        isLarge: Bool
    ) -> FileClassification {
        FileClassification(
            kind: .binary,
            detectedTypeIdentifier: contentType?.identifier,
            totalByteCount: byteCount,
            isLargeFile: isLarge
        )
    }

    private static let systemPreviewExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tif", "tiff",
        "bmp", "ico",
        "mov", "mp4", "m4v", "avi", "mkv", "mp3", "m4a", "aac", "wav", "aiff",
        "zip", "tar", "gz", "tgz", "bz2", "xz", "7z",
        "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key",
        "rtfd", "epub",
    ]
}
