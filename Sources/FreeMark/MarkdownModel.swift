import Foundation

struct MarkdownModel {
    struct Heading: Identifiable, Hashable {
        let id: UUID
        let level: Int
        let title: String
        let line: Int
    }

    enum Block: Identifiable {
        case heading(Heading)
        case paragraph(UUID, String)
        case quote(UUID, String)
        case bullet(UUID, String, checked: Bool?)
        case code(UUID, language: String?, source: String)
        case divider(UUID)
        case blank(UUID)

        var id: UUID {
            switch self {
            case .heading(let heading): heading.id
            case .paragraph(let id, _),
                 .quote(let id, _),
                 .bullet(let id, _, _),
                 .code(let id, _, _),
                 .divider(let id),
                 .blank(let id):
                id
            }
        }
    }

    let source: String
    let blocks: [Block]
    let headings: [Heading]

    init(source: String) {
        self.source = source
        var parsedBlocks: [Block] = []
        var parsedHeadings: [Heading] = []
        let lines = source.components(separatedBy: .newlines)
        var index = 0

        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                parsedBlocks.append(
                    .code(UUID(), language: language.isEmpty ? nil : language, source: code.joined(separator: "\n"))
                )
            } else if let heading = Self.heading(from: line, line: index) {
                parsedHeadings.append(heading)
                parsedBlocks.append(.heading(heading))
            } else if line.range(of: #"^\s*([-*_])(?:\s*\1){2,}\s*$"#, options: .regularExpression) != nil {
                parsedBlocks.append(.divider(UUID()))
            } else if line.hasPrefix(">") {
                parsedBlocks.append(.quote(UUID(), String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else if let item = Self.listItem(from: line) {
                parsedBlocks.append(.bullet(UUID(), item.text, checked: item.checked))
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                parsedBlocks.append(.blank(UUID()))
            } else {
                var paragraph = [line]
                while index + 1 < lines.count,
                      !Self.startsBlock(lines[index + 1]) {
                    index += 1
                    paragraph.append(lines[index])
                }
                parsedBlocks.append(.paragraph(UUID(), paragraph.joined(separator: "\n")))
            }
            index += 1
        }

        blocks = parsedBlocks
        headings = parsedHeadings
    }

    private static func heading(from line: String, line lineNumber: Int) -> Heading? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count),
              line.dropFirst(hashes.count).first == " " else { return nil }
        return Heading(
            id: UUID(),
            level: hashes.count,
            title: line.dropFirst(hashes.count + 1).trimmingCharacters(in: .whitespaces),
            line: lineNumber
        )
    }

    private static func listItem(from line: String) -> (text: String, checked: Bool?)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") else {
            return nil
        }
        var text = String(trimmed.dropFirst(2))
        if text.hasPrefix("[ ] ") {
            text = String(text.dropFirst(4))
            return (text, false)
        }
        if text.lowercased().hasPrefix("[x] ") {
            text = String(text.dropFirst(4))
            return (text, true)
        }
        return (text, nil)
    }

    private static func startsBlock(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty
            || line.hasPrefix("#")
            || line.hasPrefix(">")
            || line.hasPrefix("```")
            || listItem(from: line) != nil
            || line.range(of: #"^\s*([-*_])(?:\s*\1){2,}\s*$"#, options: .regularExpression) != nil
    }
}
