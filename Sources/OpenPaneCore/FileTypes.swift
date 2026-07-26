import CryptoKit
import Foundation

public enum FileKind: Codable, Hashable, Sendable {
    case markdown
    case text(languageID: String)
    case pdf
    case systemPreview(contentTypeIdentifier: String?)
    case binary
}

public enum FileViewMode: String, Codable, CaseIterable, Hashable, Sendable {
    case reader
    case source
    case pdf
    case systemPreview
    case rawText
    case hex
}

public struct FileClassification: Codable, Hashable, Sendable {
    public let kind: FileKind
    public let detectedTypeIdentifier: String?
    public let totalByteCount: UInt64
    public let isLargeFile: Bool

    public init(
        kind: FileKind,
        detectedTypeIdentifier: String? = nil,
        totalByteCount: UInt64,
        isLargeFile: Bool
    ) {
        self.kind = kind
        self.detectedTypeIdentifier = detectedTypeIdentifier
        self.totalByteCount = totalByteCount
        self.isLargeFile = isLargeFile
    }

    public var availableViewModes: [FileViewMode] {
        DefaultFileViewerProvider().availableViewModes(for: self)
    }

    public var defaultViewMode: FileViewMode {
        DefaultFileViewerProvider().defaultViewMode(for: self)
    }

    public var isEditable: Bool {
        DefaultFileViewerProvider().isEditable(classification: self)
    }
}

public protocol FileViewerProvider: Sendable {
    func availableViewModes(for classification: FileClassification) -> [FileViewMode]
    func defaultViewMode(for classification: FileClassification) -> FileViewMode
    func isEditable(classification: FileClassification) -> Bool
}

public struct DefaultFileViewerProvider: FileViewerProvider {
    public init() {}

    public func availableViewModes(for classification: FileClassification) -> [FileViewMode] {
        switch classification.kind {
        case .markdown:
            return classification.isLargeFile ? [.source] : [.reader, .source]
        case .text:
            return [.source]
        case .pdf:
            return [.pdf]
        case .systemPreview:
            return [.systemPreview]
        case .binary:
            return [.rawText, .hex]
        }
    }

    public func defaultViewMode(for classification: FileClassification) -> FileViewMode {
        switch classification.kind {
        case .markdown:
            return classification.isLargeFile ? .source : .reader
        case .text:
            return .source
        case .pdf:
            return .pdf
        case .systemPreview:
            return .systemPreview
        case .binary:
            return .rawText
        }
    }

    public func isEditable(classification: FileClassification) -> Bool {
        guard !classification.isLargeFile else { return false }
        switch classification.kind {
        case .markdown, .text:
            return true
        case .pdf, .systemPreview, .binary:
            return false
        }
    }
}

public struct FileIdentity: Codable, Hashable, Sendable {
    public let canonicalPath: String
    public let resourceIdentifier: String?

    public init(canonicalPath: String, resourceIdentifier: String? = nil) {
        self.canonicalPath = canonicalPath
        self.resourceIdentifier = resourceIdentifier
    }

    public init(url: URL) {
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        let values = try? resolvedURL.resourceValues(forKeys: [.fileResourceIdentifierKey])
        canonicalPath = resolvedURL.path
        resourceIdentifier = values?.fileResourceIdentifier.map(String.init(describing:))
    }
}

public enum FingerprintCoverage: String, Codable, Hashable, Sendable {
    case full
    case sampled
}

public struct FileFingerprint: Codable, Hashable, Sendable {
    public let byteCount: UInt64
    public let modificationTimeNanoseconds: Int64
    public let systemNumber: UInt64?
    public let fileNumber: UInt64?
    public let contentSHA256: String
    public let coverage: FingerprintCoverage

    public init(
        byteCount: UInt64,
        modificationTimeNanoseconds: Int64,
        systemNumber: UInt64? = nil,
        fileNumber: UInt64? = nil,
        contentSHA256: String,
        coverage: FingerprintCoverage = .full
    ) {
        self.byteCount = byteCount
        self.modificationTimeNanoseconds = modificationTimeNanoseconds
        self.systemNumber = systemNumber
        self.fileNumber = fileNumber
        self.contentSHA256 = contentSHA256
        self.coverage = coverage
    }

    public static func forData(
        _ data: Data,
        modificationDate: Date = .distantPast,
        systemNumber: UInt64? = nil,
        fileNumber: UInt64? = nil
    ) -> FileFingerprint {
        FileFingerprint(
            byteCount: UInt64(data.count),
            modificationTimeNanoseconds: modificationDate.nanosecondsSince1970,
            systemNumber: systemNumber,
            fileNumber: fileNumber,
            contentSHA256: SHA256.hash(data: data).hexString,
            coverage: .full
        )
    }

    public func hasSameContents(as other: FileFingerprint) -> Bool {
        byteCount == other.byteCount
            && contentSHA256 == other.contentSHA256
            && coverage == .full
            && other.coverage == .full
    }
}

extension Date {
    fileprivate var nanosecondsSince1970: Int64 {
        let value = timeIntervalSince1970 * 1_000_000_000
        guard value.isFinite else { return 0 }
        if value >= Double(Int64.max) { return Int64.max }
        if value <= Double(Int64.min) { return Int64.min }
        return Int64(value.rounded())
    }
}

extension Digest {
    fileprivate var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
