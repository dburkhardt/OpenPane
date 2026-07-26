import Foundation
import SwiftTreeSitter
import TreeSitterBash
import TreeSitterC
import TreeSitterCPP
import TreeSitterCSS
import TreeSitterDiff
import TreeSitterDockerfile
import TreeSitterGo
import TreeSitterHTML
import TreeSitterJava
import TreeSitterJavaScript
import TreeSitterJSON
import TreeSitterKotlin
import TreeSitterMarkdown
import TreeSitterObjc
import TreeSitterPython
import TreeSitterRust
import TreeSitterSqlBigquery
import TreeSitterSwift
import TreeSitterTOML
import TreeSitterTSX
import TreeSitterTypeScript
import TreeSitterYAML
import TreeSitterXML

enum SyntaxTokenRole: String, Sendable {
    case attribute
    case comment
    case constant
    case constructor
    case embedded
    case escape
    case function
    case keyword
    case label
    case number
    case operatorToken
    case property
    case punctuation
    case string
    case tag
    case type
    case variable
}

struct TextHighlightSpan: Equatable, Sendable {
    let range: NSRange
    let role: SyntaxTokenRole
}

/// Tree-sitter parses Swift strings as native UTF-16. OpenPane only supports
/// Apple Silicon, so the byte coordinates passed to tree-sitter are UTF-16LE
/// while AppKit continues to use UTF-16 code-unit `NSRange` values.
///
/// Keeping this conversion at the boundary avoids treating a tree-sitter byte
/// offset as an AppKit character offset, which is especially visible after an
/// accent or emoji.
enum TreeSitterUTF16LECoordinates {
    static func byteRange(fromUTF16 range: NSRange) -> Range<UInt32>? {
        guard range.location >= 0,
              range.length >= 0,
              range.location <= Int(UInt32.max) / 2,
              NSMaxRange(range) <= Int(UInt32.max) / 2 else {
            return nil
        }
        return UInt32(range.location * 2)..<UInt32(NSMaxRange(range) * 2)
    }

    static func utf16Range(fromBytes range: Range<UInt32>) -> NSRange? {
        guard range.lowerBound.isMultiple(of: 2),
              range.upperBound.isMultiple(of: 2) else {
            return nil
        }
        return NSRange(
            location: Int(range.lowerBound / 2),
            length: Int((range.upperBound - range.lowerBound) / 2)
        )
    }

    static func byteOffset(fromUTF16 offset: Int) -> UInt32 {
        UInt32(clamping: max(0, offset) * 2)
    }

    static func boundedVisibleRange(
        _ visibleRange: NSRange?,
        in source: String,
        threshold: Int = 1_000_000,
        padding: Int = 20_000
    ) -> NSRange? {
        let sourceLength = source.utf16.count
        guard sourceLength > threshold, let visibleRange else { return nil }
        let visibleStart = min(max(0, visibleRange.location), sourceLength)
        let visibleEnd = min(
            sourceLength,
            max(visibleStart, NSMaxRange(visibleRange))
        )
        let start = max(0, visibleStart - padding)
        let end = min(sourceLength, visibleEnd + padding)
        let clamped = NSRange(location: start, length: max(0, end - start))
        guard clamped.length > 0 else { return clamped }
        return (source as NSString).rangeOfComposedCharacterSequences(for: clamped)
    }
}

struct SyntaxLanguageDescriptor: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
}

enum SyntaxLanguageRegistry {
    static let bundledLanguages: [SyntaxLanguageDescriptor] = [
        .init(id: "markdown", displayName: "Markdown"),
        .init(id: "json", displayName: "JSON"),
        .init(id: "jsonc", displayName: "JSON with Comments"),
        .init(id: "python", displayName: "Python"),
        .init(id: "swift", displayName: "Swift"),
        .init(id: "bash", displayName: "Shell Script"),
        .init(id: "yaml", displayName: "YAML"),
        .init(id: "toml", displayName: "TOML"),
        .init(id: "xml", displayName: "XML"),
        .init(id: "html", displayName: "HTML"),
        .init(id: "css", displayName: "CSS"),
        .init(id: "javascript", displayName: "JavaScript"),
        .init(id: "jsx", displayName: "JavaScript JSX"),
        .init(id: "typescript", displayName: "TypeScript"),
        .init(id: "tsx", displayName: "TypeScript JSX"),
        .init(id: "c", displayName: "C"),
        .init(id: "cpp", displayName: "C++"),
        .init(id: "objective-c", displayName: "Objective-C"),
        .init(id: "go", displayName: "Go"),
        .init(id: "rust", displayName: "Rust"),
        .init(id: "java", displayName: "Java"),
        .init(id: "kotlin", displayName: "Kotlin"),
        .init(id: "sql", displayName: "SQL"),
        .init(id: "dockerfile", displayName: "Dockerfile"),
        .init(id: "diff", displayName: "Diff"),
        .init(id: "plaintext", displayName: "Plain Text")
    ]

    static func displayName(for languageID: String) -> String {
        bundledLanguages.first { $0.id == normalized(languageID) }?.displayName
            ?? languageID
    }

    static func normalized(_ languageID: String) -> String {
        switch languageID.lowercased() {
        case "md", "gfm": "markdown"
        case "py": "python"
        case "sh", "shell", "zsh": "bash"
        case "yml": "yaml"
        case "js", "node": "javascript"
        case "ts": "typescript"
        case "c++", "cc", "cxx": "cpp"
        case "objc", "objectivec": "objective-c"
        case "golang": "go"
        case "rs": "rust"
        case "kt": "kotlin"
        case "docker": "dockerfile"
        case "patch": "diff"
        case "text", "plain", "plain-text": "plaintext"
        default: languageID.lowercased()
        }
    }

    fileprivate static func configuration(for languageID: String) throws -> LanguageConfiguration? {
        switch normalized(languageID) {
        case "markdown":
            try bundledConfiguration(tree_sitter_markdown(), name: "Markdown")
        case "json", "jsonc":
            try bundledConfiguration(tree_sitter_json(), name: "JSON")
        case "python":
            try bundledConfiguration(tree_sitter_python(), name: "Python")
        case "swift":
            try bundledConfiguration(tree_sitter_swift(), name: "Swift")
        case "bash":
            try bundledConfiguration(tree_sitter_bash(), name: "Bash")
        case "yaml":
            try configuration(
                language: Language(tree_sitter_yaml()),
                name: "YAML",
                highlights: """
                (comment) @comment
                [
                  (double_quote_scalar)
                  (single_quote_scalar)
                  (block_scalar)
                  (string_scalar)
                ] @string
                [
                  (integer_scalar)
                  (float_scalar)
                ] @number
                (boolean_scalar) @boolean
                (null_scalar) @constant.builtin
                [
                  (anchor)
                  (alias)
                ] @label
                (tag) @tag
                (block_mapping_pair key: (_) @property)
                """
            )
        case "toml":
            try bundledConfiguration(tree_sitter_toml(), name: "TOML")
        case "xml":
            try bundledConfiguration(tree_sitter_xml(), name: "XML")
        case "html":
            try bundledConfiguration(tree_sitter_html(), name: "HTML")
        case "css":
            try bundledConfiguration(tree_sitter_css(), name: "CSS")
        case "javascript", "jsx":
            try bundledConfiguration(
                tree_sitter_javascript(),
                name: "JavaScript"
            )
        case "typescript":
            try bundledConfiguration(
                tree_sitter_typescript(),
                name: "TypeScript",
                bundleName: "TreeSitterTypeScript_TreeSitterTypeScript"
            )
        case "tsx":
            try bundledConfiguration(
                tree_sitter_tsx(),
                name: "TSX",
                bundleName: "TreeSitterTypeScript_TreeSitterTSX"
            )
        case "c":
            try bundledConfiguration(tree_sitter_c(), name: "C")
        case "cpp":
            try bundledConfiguration(tree_sitter_cpp(), name: "CPP")
        case "objective-c":
            try bundledConfiguration(tree_sitter_objc(), name: "Objc")
        case "go":
            try bundledConfiguration(tree_sitter_go(), name: "Go")
        case "rust":
            try bundledConfiguration(tree_sitter_rust(), name: "Rust")
        case "java":
            try bundledConfiguration(tree_sitter_java(), name: "Java")
        case "kotlin":
            try configuration(
                language: Language(tree_sitter_kotlin()),
                name: "Kotlin",
                highlights: """
                [
                  (line_comment)
                  (block_comment)
                ] @comment
                [
                  (string_literal)
                  (multiline_string_literal)
                  (character_literal)
                ] @string
                (escape_sequence) @string.escape
                [
                  (number_literal)
                  (float_literal)
                ] @number
                [
                  "as" "as?" "class" "data" "else" "enum" "for" "fun"
                  "if" "import" "in" "interface" "is" "object" "package"
                  "return" "this" "throw" "try" "typealias" "val" "var"
                  "when" "where" "while"
                ] @keyword
                (function_declaration (identifier) @function)
                (class_declaration (identifier) @type)
                """
            )
        case "sql":
            try bundledConfiguration(
                tree_sitter_sql_bigquery(),
                name: "SqlBigquery"
            )
        case "dockerfile":
            try bundledConfiguration(
                tree_sitter_dockerfile(),
                name: "Dockerfile"
            )
        case "diff":
            try bundledConfiguration(tree_sitter_diff(), name: "Diff")
        default:
            nil
        }
    }

    private static func configuration(
        language: Language,
        name: String,
        highlights: String
    ) throws -> LanguageConfiguration {
        let query = try Query(language: language, data: Data(highlights.utf8))
        return LanguageConfiguration(
            language,
            name: name,
            queries: [.highlights: query]
        )
    }

    private static func bundledConfiguration(
        _ pointer: OpaquePointer,
        name: String,
        bundleName: String? = nil
    ) throws -> LanguageConfiguration {
        let language = Language(pointer)
        let resolvedBundleName = bundleName
            ?? "TreeSitter\(name)_TreeSitter\(name)"
        if let configuration = try? LanguageConfiguration(
            language,
            name: name,
            bundleName: resolvedBundleName
        ), configuration.queries[.highlights] != nil {
            return configuration
        }

        // SwiftPM keeps dependency resource bundles beside its test bundle,
        // while the packaged app keeps them in Contents/Resources. Search
        // those executable ancestors as a test/runtime fallback without
        // hard-coding a checkout or build directory.
        guard let queryURL = highlightsQueryURL(
            bundleName: resolvedBundleName
        ) else {
            return LanguageConfiguration(language, name: name, queries: [:])
        }
        let query = try Query(language: language, url: queryURL)
        return LanguageConfiguration(
            language,
            name: name,
            queries: [.highlights: query]
        )
    }

    private static func highlightsQueryURL(bundleName: String) -> URL? {
        var directories: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            directories.append(resourceURL)
        }

        func appendAncestors(of url: URL?) {
            guard var directory = url?.deletingLastPathComponent() else {
                return
            }
            for _ in 0..<7 {
                directories.append(directory)
                directory.deleteLastPathComponent()
            }
        }
        appendAncestors(of: Bundle.main.executableURL)
        for argument in ProcessInfo.processInfo.arguments where argument.hasPrefix("/") {
            appendAncestors(of: URL(filePath: argument))
        }

        // The SwiftPM testing helper can be the main executable instead of
        // the xctest bundle. Its working directory remains the package root.
        let buildDirectory = URL(
            filePath: FileManager.default.currentDirectoryPath
        ).appending(path: ".build", directoryHint: .isDirectory)
        if let triples = try? FileManager.default.contentsOfDirectory(
            at: buildDirectory,
            includingPropertiesForKeys: nil
        ) {
            for triple in triples {
                directories.append(triple.appending(path: "debug"))
                directories.append(triple.appending(path: "release"))
            }
        }

        for directory in directories {
            let bundleURL = directory.appending(
                path: "\(bundleName).bundle",
                directoryHint: .isDirectory
            )
            let candidates = [
                bundleURL.appending(path: "queries/highlights.scm"),
                bundleURL.appending(
                    path: "Contents/Resources/queries/highlights.scm"
                )
            ]
            if let match = candidates.first(where: {
                FileManager.default.isReadableFile(atPath: $0.path)
            }) {
                return match
            }
        }
        return nil
    }
}

/// Keeps a tree-sitter parse tree alive between edits. The editor supplies the
/// exact replacement range when possible, allowing tree-sitter to reparse only
/// the affected syntax rather than rebuilding the tree on every keystroke.
@MainActor
final class IncrementalSyntaxHighlighter {
    struct Edit: Sendable {
        let range: NSRange
        let replacement: String
    }

    private var languageID = "plaintext"
    private var parser: Parser?
    private var configuration: LanguageConfiguration?
    private var tree: MutableTree?
    private var source = ""

    var hasActiveGrammar: Bool {
        parser != nil && configuration != nil
    }

    func setLanguage(_ newLanguageID: String) {
        let normalized = SyntaxLanguageRegistry.normalized(newLanguageID)
        guard normalized != languageID else { return }

        languageID = normalized
        parser = nil
        configuration = nil
        tree = nil
        source = ""

        guard let config = try? SyntaxLanguageRegistry.configuration(for: normalized) else {
            return
        }

        let newParser = Parser()
        guard (try? newParser.setLanguage(config.language)) != nil else { return }
        newParser.timeout = 0.08
        parser = newParser
        configuration = config
    }

    func highlights(
        in newSource: String,
        edit: Edit? = nil,
        visibleRange: NSRange? = nil
    ) -> [TextHighlightSpan] {
        defer { source = newSource }

        guard let parser, let configuration else {
            return fallbackHighlights(in: newSource, visibleRange: visibleRange)
        }

        let appliedEdit = edit ?? inferredEdit(from: source, to: newSource)
        if let tree, let appliedEdit {
            tree.edit(inputEdit(for: appliedEdit, oldSource: source, newSource: newSource))
        } else if source != newSource {
            tree = nil
        }

        guard let newTree = parser.parse(tree: tree, string: newSource) else {
            return fallbackHighlights(in: newSource, visibleRange: visibleRange)
        }
        tree = newTree

        guard let query = configuration.queries[.highlights] else {
            return fallbackHighlights(in: newSource, visibleRange: visibleRange)
        }

        let cursor = query.execute(in: newTree)
        let queryRange = boundedQueryRange(visibleRange, in: newSource)
        if let queryRange,
           let byteRange = TreeSitterUTF16LECoordinates.byteRange(fromUTF16: queryRange) {
            cursor.setByteRange(range: byteRange)
        }

        let context = Predicate.Context(string: newSource)
        return cursor
            .resolve(with: context)
            .highlights()
            .compactMap { namedRange in
                guard let range = TreeSitterUTF16LECoordinates.utf16Range(
                    fromBytes: namedRange.tsRange.bytes
                ) else {
                    return nil
                }
                guard range.location >= 0,
                      range.length >= 0,
                      NSMaxRange(range) <= newSource.utf16.count else {
                    return nil
                }
                return TextHighlightSpan(
                    range: range,
                    role: tokenRole(for: namedRange.nameComponents)
                )
            }
    }

    private func inputEdit(
        for edit: Edit,
        oldSource: String,
        newSource: String
    ) -> InputEdit {
        let oldLength = oldSource.utf16.count
        let start = min(max(0, edit.range.location), oldLength)
        let oldEnd = min(max(start, NSMaxRange(edit.range)), oldLength)
        let newEnd = min(start + edit.replacement.utf16.count, newSource.utf16.count)

        return InputEdit(
            startByte: TreeSitterUTF16LECoordinates.byteOffset(fromUTF16: start),
            oldEndByte: TreeSitterUTF16LECoordinates.byteOffset(fromUTF16: oldEnd),
            newEndByte: TreeSitterUTF16LECoordinates.byteOffset(fromUTF16: newEnd),
            startPoint: point(in: oldSource, at: start),
            oldEndPoint: point(in: oldSource, at: oldEnd),
            newEndPoint: point(in: newSource, at: newEnd)
        )
    }

    private func point(in value: String, at utf16Offset: Int) -> Point {
        let units = value.utf16
        let end = units.index(
            units.startIndex,
            offsetBy: min(max(0, utf16Offset), units.count)
        )
        var row = 0
        var columnUnits = 0

        for unit in units[..<end] {
            if unit == 0x0A {
                row += 1
                columnUnits = 0
            } else {
                columnUnits += 1
            }
        }
        return Point(
            row: row,
            column: Int(TreeSitterUTF16LECoordinates.byteOffset(fromUTF16: columnUnits))
        )
    }

    private func inferredEdit(from oldValue: String, to newValue: String) -> Edit? {
        guard oldValue != newValue else { return nil }
        let old = Array(oldValue.utf16)
        let new = Array(newValue.utf16)
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] {
            prefix += 1
        }
        // Two different emoji frequently share a high surrogate. Never begin
        // an incremental edit between the two halves of a scalar.
        if prefix > 0,
           prefix < old.count,
           isLowSurrogate(old[prefix]),
           isHighSurrogate(old[prefix - 1]) {
            prefix -= 1
        }

        var oldSuffix = old.count
        var newSuffix = new.count
        while oldSuffix > prefix,
              newSuffix > prefix,
              old[oldSuffix - 1] == new[newSuffix - 1] {
            oldSuffix -= 1
            newSuffix -= 1
        }
        if oldSuffix > prefix,
           oldSuffix < old.count,
           isLowSurrogate(old[oldSuffix]),
           isHighSurrogate(old[oldSuffix - 1]) {
            oldSuffix += 1
        }
        if newSuffix > prefix,
           newSuffix < new.count,
           isLowSurrogate(new[newSuffix]),
           isHighSurrogate(new[newSuffix - 1]) {
            newSuffix += 1
        }

        let replacementUnits = new[prefix..<newSuffix]
        let replacement = String(decoding: replacementUnits, as: UTF16.self)
        return Edit(
            range: NSRange(location: prefix, length: oldSuffix - prefix),
            replacement: replacement
        )
    }

    private func boundedQueryRange(
        _ visibleRange: NSRange?,
        in source: String
    ) -> NSRange? {
        TreeSitterUTF16LECoordinates.boundedVisibleRange(
            visibleRange,
            in: source
        )
    }

    private func isHighSurrogate(_ unit: UInt16) -> Bool {
        (0xD800...0xDBFF).contains(unit)
    }

    private func isLowSurrogate(_ unit: UInt16) -> Bool {
        (0xDC00...0xDFFF).contains(unit)
    }

    private func tokenRole(for components: [String]) -> SyntaxTokenRole {
        let names = Set(components)
        if names.contains("comment") { return .comment }
        if names.contains("string") { return .string }
        if names.contains("escape") { return .escape }
        if names.contains("keyword") { return .keyword }
        if names.contains("number") || names.contains("float") { return .number }
        if names.contains("boolean") || names.contains("constant") { return .constant }
        if names.contains("type") { return .type }
        if names.contains("constructor") { return .constructor }
        if names.contains("function") || names.contains("method") { return .function }
        if names.contains("property") || names.contains("field") { return .property }
        if names.contains("variable") || names.contains("parameter") { return .variable }
        if names.contains("operator") { return .operatorToken }
        if names.contains("tag") { return .tag }
        if names.contains("attribute") { return .attribute }
        if names.contains("label") { return .label }
        if names.contains("embedded") { return .embedded }
        return .punctuation
    }

    private func fallbackHighlights(
        in value: String,
        visibleRange: NSRange?
    ) -> [TextHighlightSpan] {
        let patterns: [(String, SyntaxTokenRole)]
        switch languageID {
        case "objective-c":
            patterns = [
                (#"//.*|/\*[\s\S]*?\*/"#, .comment),
                (#"@"(?:\\.|[^"\\])*""#, .string),
                (#"\b(?:@interface|@implementation|@end|@property|@protocol|@selector|id|instancetype|BOOL|YES|NO|nil)\b"#, .keyword),
                (#"\b\d+(?:\.\d+)?\b"#, .number)
            ]
        case "kotlin":
            patterns = [
                (#"//.*|/\*[\s\S]*?\*/"#, .comment),
                (#""(?:\\.|[^"\\])*""#, .string),
                (#"\b(?:class|interface|object|fun|val|var|when|is|in|as|return|suspend|data|sealed|companion)\b"#, .keyword),
                (#"\b\d+(?:\.\d+)?\b"#, .number)
            ]
        case "xml":
            patterns = [
                (#"<!--[\s\S]*?-->"#, .comment),
                (#"</?[A-Za-z_][^>]*?>"#, .tag),
                (#"\b[A-Za-z_:][-A-Za-z0-9_:.]*(?=\s*=)"#, .attribute),
                (#""(?:\\.|[^"\\])*""#, .string)
            ]
        case "sql":
            patterns = [
                (#"--.*|/\*[\s\S]*?\*/"#, .comment),
                (#"'(?:''|[^'])*'"#, .string),
                (#"\b(?:SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|OUTER|ON|GROUP|BY|ORDER|HAVING|LIMIT|OFFSET|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|ALTER|DROP|TABLE|VIEW|INDEX|WITH|AS|CASE|WHEN|THEN|ELSE|END|AND|OR|NOT|NULL|IS|IN|EXISTS|DISTINCT|UNION|ALL|RETURNING)\b"#, .keyword),
                (#"\b[-+]?\d+(?:\.\d+)?\b"#, .number)
            ]
        default:
            return []
        }

        let searchRange = boundedQueryRange(visibleRange, in: value)
            ?? NSRange(location: 0, length: value.utf16.count)
        return patterns.flatMap { pattern, role in
            guard let expression = try? NSRegularExpression(
                pattern: pattern,
                options: [.anchorsMatchLines]
            ) else {
                return [TextHighlightSpan]()
            }
            return expression.matches(in: value, range: searchRange).map {
                TextHighlightSpan(range: $0.range, role: role)
            }
        }
    }
}
