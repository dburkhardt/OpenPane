import Foundation

public enum BinaryTextRenderer {
    public static func render(
        _ data: Data,
        encoding: TextEncoding = .utf8,
        maximumByteCount: Int? = nil
    ) -> String {
        let visibleData: Data
        let wasTruncated: Bool
        if let maximumByteCount, data.count > maximumByteCount {
            visibleData = Data(data.prefix(maximumByteCount))
            wasTruncated = true
        } else {
            visibleData = data
            wasTruncated = false
        }

        let rendered: String
        if encoding == .utf8 {
            rendered = renderUTF8(visibleData)
        } else if isSingleByte(encoding) {
            rendered = renderSingleByte(visibleData, encoding: encoding)
        } else if let decoded = String(data: visibleData, encoding: encoding.foundationEncoding) {
            rendered = makeControlsVisible(decoded)
        } else {
            rendered = visibleData.map(invalidByteMarker).joined()
        }

        if wasTruncated {
            return rendered + "\n\n… \(data.count - visibleData.count) bytes not shown"
        }
        return rendered
    }

    private static func renderUTF8(_ data: Data) -> String {
        let bytes = Array(data)
        var output = ""
        var index = 0

        while index < bytes.count {
            let byte = bytes[index]
            if byte < 0x80 {
                output += visibleASCII(byte)
                index += 1
                continue
            }

            let length: Int
            switch byte {
            case 0xC2...0xDF: length = 2
            case 0xE0...0xEF: length = 3
            case 0xF0...0xF4: length = 4
            default:
                output += invalidByteMarker(byte)
                index += 1
                continue
            }

            guard index + length <= bytes.count else {
                output += bytes[index...].map(invalidByteMarker).joined()
                break
            }

            let candidate = Data(bytes[index..<(index + length)])
            if let string = String(data: candidate, encoding: .utf8) {
                output += makeControlsVisible(string)
                index += length
            } else {
                output += invalidByteMarker(byte)
                index += 1
            }
        }
        return output
    }

    private static func renderSingleByte(_ data: Data, encoding: TextEncoding) -> String {
        data.map { byte in
            if byte < 0x80 {
                return visibleASCII(byte)
            }
            let scalar = String(data: Data([byte]), encoding: encoding.foundationEncoding)
            return scalar.map(makeControlsVisible) ?? invalidByteMarker(byte)
        }.joined()
    }

    private static func makeControlsVisible(_ text: String) -> String {
        var output = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0A:
                output += "↵\n"
            case 0x0D:
                output += "␍"
            case 0x09:
                output += "⇥"
            case 0x00...0x1F:
                output.unicodeScalars.append(Unicode.Scalar(0x2400 + scalar.value)!)
            case 0x7F:
                output += "␡"
            case 0x80...0x9F:
                output += "‹U+\(String(format: "%04X", scalar.value))›"
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        return output
    }

    private static func visibleASCII(_ byte: UInt8) -> String {
        switch byte {
        case 0x0A: "↵\n"
        case 0x0D: "␍"
        case 0x09: "⇥"
        case 0x00...0x1F:
            String(Unicode.Scalar(0x2400 + UInt32(byte))!)
        case 0x7F: "␡"
        default: String(Unicode.Scalar(byte))
        }
    }

    private static func invalidByteMarker(_ byte: UInt8) -> String {
        "‹\(String(format: "%02X", byte))›"
    }

    private static func isSingleByte(_ encoding: TextEncoding) -> Bool {
        switch encoding {
        case .windows1252, .isoLatin1, .macOSRoman:
            true
        case .utf8, .utf16LittleEndian, .utf16BigEndian,
             .utf32LittleEndian, .utf32BigEndian:
            false
        }
    }
}

public struct HexRow: Equatable, Identifiable, Sendable {
    public var id: Int { offset }
    public let offset: Int
    public let bytes: [UInt8]
    public let hexadecimal: String
    public let ascii: String

    public init(offset: Int, bytes: [UInt8], bytesPerRow: Int = 16) {
        self.offset = offset
        self.bytes = bytes
        let values = bytes.map { String(format: "%02X", $0) }
        let padding = Array(repeating: "  ", count: max(0, bytesPerRow - bytes.count))
        hexadecimal = (values + padding).joined(separator: " ")
        ascii = bytes.map { byte in
            (0x20...0x7E).contains(byte) ? String(Unicode.Scalar(byte)) : "·"
        }.joined()
    }

    public var formattedOffset: String {
        String(format: "%08X", offset)
    }
}

public enum HexRenderer {
    public static func rows(
        for data: Data,
        bytesPerRow: Int = 16,
        maximumByteCount: Int? = nil
    ) -> [HexRow] {
        let width = max(1, bytesPerRow)
        let count = min(data.count, maximumByteCount ?? data.count)
        let bytes = Array(data.prefix(count))
        return stride(from: 0, to: bytes.count, by: width).map { offset in
            let end = min(offset + width, bytes.count)
            return HexRow(
                offset: offset,
                bytes: Array(bytes[offset..<end]),
                bytesPerRow: width
            )
        }
    }
}
