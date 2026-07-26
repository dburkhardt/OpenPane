import Foundation

public enum TextEncoding: String, Codable, CaseIterable, Hashable, Sendable {
    case utf8
    case utf16LittleEndian
    case utf16BigEndian
    case utf32LittleEndian
    case utf32BigEndian
    case windows1252
    case isoLatin1
    case macOSRoman

    public var displayName: String {
        switch self {
        case .utf8: "UTF-8"
        case .utf16LittleEndian: "UTF-16 LE"
        case .utf16BigEndian: "UTF-16 BE"
        case .utf32LittleEndian: "UTF-32 LE"
        case .utf32BigEndian: "UTF-32 BE"
        case .windows1252: "Windows-1252"
        case .isoLatin1: "ISO-8859-1"
        case .macOSRoman: "Mac OS Roman"
        }
    }

    var foundationEncoding: String.Encoding {
        switch self {
        case .utf8: .utf8
        case .utf16LittleEndian: .utf16LittleEndian
        case .utf16BigEndian: .utf16BigEndian
        case .utf32LittleEndian: .utf32LittleEndian
        case .utf32BigEndian: .utf32BigEndian
        case .windows1252: .windowsCP1252
        case .isoLatin1: .isoLatin1
        case .macOSRoman: .macOSRoman
        }
    }
}

public enum ByteOrderMark: String, Codable, CaseIterable, Hashable, Sendable {
    case none
    case utf8
    case utf16LittleEndian
    case utf16BigEndian
    case utf32LittleEndian
    case utf32BigEndian

    public var bytes: Data {
        switch self {
        case .none: Data()
        case .utf8: Data([0xEF, 0xBB, 0xBF])
        case .utf16LittleEndian: Data([0xFF, 0xFE])
        case .utf16BigEndian: Data([0xFE, 0xFF])
        case .utf32LittleEndian: Data([0xFF, 0xFE, 0x00, 0x00])
        case .utf32BigEndian: Data([0x00, 0x00, 0xFE, 0xFF])
        }
    }
}

public enum LineEndingConvention: String, Codable, CaseIterable, Hashable, Sendable {
    case none
    case lf
    case crlf
    case cr
    case mixed
}

public struct TextFileMetadata: Codable, Equatable, Sendable {
    public var encoding: TextEncoding
    public var byteOrderMark: ByteOrderMark
    public var lineEndings: LineEndingConvention
    /// The original separator for each line break when a file uses mixed line
    /// endings. This lets ordinary edits preserve the existing byte convention
    /// instead of silently normalizing the whole file.
    public var originalLineEndings: [LineEndingConvention]?
    public var hasTrailingNewline: Bool
    public var originalByteCount: UInt64
    public var posixPermissions: UInt16?
    public var isExecutable: Bool
    public var extendedAttributes: [String: Data]
    public var sourceFingerprint: FileFingerprint?

    public init(
        encoding: TextEncoding,
        byteOrderMark: ByteOrderMark = .none,
        lineEndings: LineEndingConvention = .none,
        originalLineEndings: [LineEndingConvention]? = nil,
        hasTrailingNewline: Bool = false,
        originalByteCount: UInt64 = 0,
        posixPermissions: UInt16? = nil,
        isExecutable: Bool = false,
        extendedAttributes: [String: Data] = [:],
        sourceFingerprint: FileFingerprint? = nil
    ) {
        self.encoding = encoding
        self.byteOrderMark = byteOrderMark
        self.lineEndings = lineEndings
        self.originalLineEndings = originalLineEndings
        self.hasTrailingNewline = hasTrailingNewline
        self.originalByteCount = originalByteCount
        self.posixPermissions = posixPermissions
        self.isExecutable = isExecutable
        self.extendedAttributes = extendedAttributes
        self.sourceFingerprint = sourceFingerprint
    }
}

public struct DecodedText: Equatable, Sendable {
    /// Text normalized to LF line endings for the editor.
    public let text: String
    /// The exact decoded string before line-ending normalization.
    public let originalText: String
    /// The original bytes, retained so a no-op save can be byte-identical.
    public let originalData: Data
    public let metadata: TextFileMetadata

    public init(
        text: String,
        originalText: String,
        originalData: Data,
        metadata: TextFileMetadata
    ) {
        self.text = text
        self.originalText = originalText
        self.originalData = originalData
        self.metadata = metadata
    }
}

public enum TextCodecError: Error, Equatable, LocalizedError, Sendable {
    case invalidText
    case cannotRepresent(TextEncoding)

    public var errorDescription: String? {
        switch self {
        case .invalidText:
            "The bytes do not contain supported text."
        case let .cannotRepresent(encoding):
            "The edited text cannot be represented as \(encoding.displayName) without data loss."
        }
    }
}

public enum TextCodec {
    private static let legacyEncodings: [TextEncoding] = [
        .windows1252,
        .isoLatin1,
        .macOSRoman,
    ]

    public static func decode(
        _ data: Data,
        allowLegacyEncodings: Bool = true
    ) -> DecodedText? {
        let detected = detectedUnicodeEncoding(in: data)
        let candidates: [(TextEncoding, ByteOrderMark, Data)]

        if let detected {
            candidates = [(
                detected.encoding,
                detected.byteOrderMark,
                data.dropPrefix(detected.byteOrderMark.bytes.count)
            )]
        } else {
            var values: [(TextEncoding, ByteOrderMark, Data)] = [
                (.utf8, .none, data),
            ]
            if allowLegacyEncodings {
                values.append(contentsOf: legacyEncodings.map { ($0, .none, data) })
            }
            candidates = values
        }

        for (encoding, byteOrderMark, payload) in candidates {
            guard let originalText = String(data: payload, encoding: encoding.foundationEncoding),
                  isLosslessRoundTrip(originalText, payload: payload, encoding: encoding),
                  looksLikeText(originalText)
            else {
                continue
            }

            let lineEndings = lineEndingConvention(in: originalText)
            let metadata = TextFileMetadata(
                encoding: encoding,
                byteOrderMark: byteOrderMark,
                lineEndings: lineEndings,
                originalLineEndings: lineEndings == .mixed
                    ? lineEndingSequence(in: originalText)
                    : nil,
                hasTrailingNewline: hasTrailingNewline(originalText),
                originalByteCount: UInt64(data.count)
            )
            return DecodedText(
                text: normalizeLineEndings(originalText),
                originalText: originalText,
                originalData: data,
                metadata: metadata
            )
        }
        return nil
    }

    public static func decodeOrThrow(
        _ data: Data,
        allowLegacyEncodings: Bool = true
    ) throws -> DecodedText {
        guard let value = decode(data, allowLegacyEncodings: allowLegacyEncodings) else {
            throw TextCodecError.invalidText
        }
        return value
    }

    public static func encode(
        _ text: String,
        metadata: TextFileMetadata,
        originalText: String? = nil,
        originalData: Data? = nil
    ) throws -> Data {
        if let originalText, let originalData,
           text == normalizeLineEndings(originalText)
        {
            return originalData
        }

        let lineEndingText = applyLineEndings(text, metadata: metadata)
        guard let payload = lineEndingText.data(
            using: metadata.encoding.foundationEncoding,
            allowLossyConversion: false
        ) else {
            throw TextCodecError.cannotRepresent(metadata.encoding)
        }

        var result = metadata.byteOrderMark.bytes
        result.append(payload)
        return result
    }

    public static func encode(_ text: String, preserving decoded: DecodedText) throws -> Data {
        try encode(
            text,
            metadata: decoded.metadata,
            originalText: decoded.originalText,
            originalData: decoded.originalData
        )
    }

    public static func normalizeLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    public static func lineEndingConvention(in text: String) -> LineEndingConvention {
        var lf = 0
        var crlf = 0
        var cr = 0
        let scalars = text.unicodeScalars
        var index = scalars.startIndex

        while index < scalars.endIndex {
            switch scalars[index].value {
            case 0x0D:
                let next = scalars.index(after: index)
                if next < scalars.endIndex, scalars[next].value == 0x0A {
                    crlf += 1
                    index = scalars.index(after: next)
                } else {
                    cr += 1
                    index = next
                }
            case 0x0A:
                lf += 1
                index = scalars.index(after: index)
            default:
                index = scalars.index(after: index)
            }
        }

        let kinds = [lf, crlf, cr].filter { $0 > 0 }.count
        if kinds == 0 { return .none }
        if kinds > 1 { return .mixed }
        if crlf > 0 { return .crlf }
        if cr > 0 { return .cr }
        return .lf
    }

    public static func lineEndingSequence(in text: String) -> [LineEndingConvention] {
        var result: [LineEndingConvention] = []
        let scalars = text.unicodeScalars
        var index = scalars.startIndex

        while index < scalars.endIndex {
            switch scalars[index].value {
            case 0x0D:
                let next = scalars.index(after: index)
                if next < scalars.endIndex, scalars[next].value == 0x0A {
                    result.append(.crlf)
                    index = scalars.index(after: next)
                } else {
                    result.append(.cr)
                    index = next
                }
            case 0x0A:
                result.append(.lf)
                index = scalars.index(after: index)
            default:
                index = scalars.index(after: index)
            }
        }
        return result
    }

    public static func looksLikeText(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }

        var scalars = 0
        var suspiciousControls = 0
        var nulls = 0
        for scalar in text.unicodeScalars.prefix(65_536) {
            scalars += 1
            switch scalar.value {
            case 0:
                nulls += 1
            case 0x01...0x08, 0x0B, 0x0E...0x1F, 0x7F...0x9F:
                suspiciousControls += 1
            default:
                break
            }
        }

        guard nulls == 0 else { return false }
        let allowedControls = max(2, scalars / 100)
        return suspiciousControls <= allowedControls
    }

    private static func detectedUnicodeEncoding(
        in data: Data
    ) -> (encoding: TextEncoding, byteOrderMark: ByteOrderMark)? {
        // UTF-32 marks must be checked before their UTF-16 prefixes.
        if data.starts(with: ByteOrderMark.utf32LittleEndian.bytes) {
            return (.utf32LittleEndian, .utf32LittleEndian)
        }
        if data.starts(with: ByteOrderMark.utf32BigEndian.bytes) {
            return (.utf32BigEndian, .utf32BigEndian)
        }
        if data.starts(with: ByteOrderMark.utf8.bytes) {
            return (.utf8, .utf8)
        }
        if data.starts(with: ByteOrderMark.utf16LittleEndian.bytes) {
            return (.utf16LittleEndian, .utf16LittleEndian)
        }
        if data.starts(with: ByteOrderMark.utf16BigEndian.bytes) {
            return (.utf16BigEndian, .utf16BigEndian)
        }
        return nil
    }

    private static func isLosslessRoundTrip(
        _ string: String,
        payload: Data,
        encoding: TextEncoding
    ) -> Bool {
        string.data(using: encoding.foundationEncoding, allowLossyConversion: false) == payload
    }

    private static func hasTrailingNewline(_ text: String) -> Bool {
        guard let last = text.unicodeScalars.last else { return false }
        return last.value == 0x0A || last.value == 0x0D
    }

    private static func applyLineEndings(
        _ text: String,
        metadata: TextFileMetadata
    ) -> String {
        let normalized = normalizeLineEndings(text)
        switch metadata.lineEndings {
        case .crlf:
            return normalized.replacingOccurrences(of: "\n", with: "\r\n")
        case .cr:
            return normalized.replacingOccurrences(of: "\n", with: "\r")
        case .mixed:
            return applyMixedLineEndings(
                normalized,
                originalSequence: metadata.originalLineEndings ?? []
            )
        case .none, .lf:
            return normalized
        }
    }

    private static func applyMixedLineEndings(
        _ normalized: String,
        originalSequence: [LineEndingConvention]
    ) -> String {
        guard normalized.contains("\n") else { return normalized }

        let fallback = dominantLineEnding(in: originalSequence) ?? .lf
        let parts = normalized.components(separatedBy: "\n")
        var result = ""
        result.reserveCapacity(normalized.utf8.count + parts.count)

        for index in parts.indices {
            result.append(parts[index])
            guard index < parts.count - 1 else { continue }
            let separator = index < originalSequence.count
                ? originalSequence[index]
                : fallback
            switch separator {
            case .crlf:
                result.append("\r\n")
            case .cr:
                result.append("\r")
            case .none, .lf, .mixed:
                result.append("\n")
            }
        }
        return result
    }

    private static func dominantLineEnding(
        in sequence: [LineEndingConvention]
    ) -> LineEndingConvention? {
        let supported: [LineEndingConvention] = [.crlf, .lf, .cr]
        return supported.max { left, right in
            sequence.count { $0 == left } < sequence.count { $0 == right }
        }.flatMap { sequence.contains($0) ? $0 : nil }
    }
}

private extension Data {
    func dropPrefix(_ count: Int) -> Data {
        guard count > 0 else { return self }
        return Data(dropFirst(count))
    }
}
