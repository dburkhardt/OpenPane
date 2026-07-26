import Foundation

public struct BracketPair: Codable, Hashable, Sendable {
    public let opening: String
    public let closing: String

    public init(_ opening: String, _ closing: String) {
        self.opening = opening
        self.closing = closing
    }
}

public struct BlockComment: Codable, Hashable, Sendable {
    public let opening: String
    public let closing: String

    public init(_ opening: String, _ closing: String) {
        self.opening = opening
        self.closing = closing
    }
}

public struct LanguageDefinition: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let exactFilenames: Set<String>
    public let filenameExtensions: Set<String>
    public let shebangTokens: Set<String>
    public let lineComment: String?
    public let blockComment: BlockComment?
    public let bracketPairs: [BracketPair]

    public init(
        id: String,
        displayName: String,
        exactFilenames: Set<String> = [],
        filenameExtensions: Set<String> = [],
        shebangTokens: Set<String> = [],
        lineComment: String? = nil,
        blockComment: BlockComment? = nil,
        bracketPairs: [BracketPair] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.exactFilenames = Set(exactFilenames.map { $0.lowercased() })
        self.filenameExtensions = Set(filenameExtensions.map { $0.lowercased() })
        self.shebangTokens = Set(shebangTokens.map { $0.lowercased() })
        self.lineComment = lineComment
        self.blockComment = blockComment
        self.bracketPairs = bracketPairs
    }
}

public struct LanguageRegistry: Sendable {
    public static let builtIn = LanguageRegistry(definitions: builtInDefinitions)

    public let definitions: [LanguageDefinition]
    private let definitionsByID: [String: LanguageDefinition]
    private let definitionsByFilename: [String: LanguageDefinition]
    private let definitionsByExtension: [String: LanguageDefinition]

    public init(definitions: [LanguageDefinition]) {
        self.definitions = definitions
        definitionsByID = Dictionary(
            definitions.map { ($0.id.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var filenames: [String: LanguageDefinition] = [:]
        var extensions: [String: LanguageDefinition] = [:]
        for definition in definitions {
            for filename in definition.exactFilenames where filenames[filename] == nil {
                filenames[filename] = definition
            }
            for pathExtension in definition.filenameExtensions where extensions[pathExtension] == nil {
                extensions[pathExtension] = definition
            }
        }
        definitionsByFilename = filenames
        definitionsByExtension = extensions
    }

    public func definition(id: String) -> LanguageDefinition? {
        definitionsByID[id.lowercased()]
    }

    /// Detection precedence is manual override, exact filename, extension,
    /// shebang, content sniffing, then plain text.
    public func detect(
        filename: String,
        contentPrefix: String = "",
        manualOverride: String? = nil
    ) -> LanguageDefinition {
        if let manualOverride, let definition = definition(id: manualOverride) {
            return definition
        }

        let lowercaseFilename = filename.lowercased()
        if let definition = definitionsByFilename[lowercaseFilename] {
            return definition
        }

        let pathExtension = URL(fileURLWithPath: lowercaseFilename).pathExtension
        if !pathExtension.isEmpty, let definition = definitionsByExtension[pathExtension] {
            return definition
        }

        if let shebang = contentPrefix.split(whereSeparator: \.isNewline).first,
           shebang.hasPrefix("#!")
        {
            let lowercaseShebang = shebang.lowercased()
            if let definition = definitions.first(where: {
                !$0.shebangTokens.isEmpty
                    && $0.shebangTokens.contains(where: lowercaseShebang.contains)
            }) {
                return definition
            }
        }

        if let contentID = sniffContentID(contentPrefix),
           let definition = definition(id: contentID)
        {
            return definition
        }

        return definition(id: "plaintext") ?? Self.plainText
    }

    public func isKnownTextFilename(_ filename: String) -> Bool {
        let lowercaseFilename = filename.lowercased()
        if definitionsByFilename[lowercaseFilename] != nil { return true }
        let pathExtension = URL(fileURLWithPath: lowercaseFilename).pathExtension
        return !pathExtension.isEmpty && definitionsByExtension[pathExtension] != nil
    }

    private func sniffContentID(_ content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercase = trimmed.lowercased()

        if lowercase.hasPrefix("diff --git ") || lowercase.hasPrefix("@@ ") {
            return "diff"
        }
        if lowercase.hasPrefix("<?xml") {
            return "xml"
        }
        if lowercase.hasPrefix("<!doctype html") || lowercase.hasPrefix("<html") {
            return "html"
        }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return "json"
        }
        if lowercase.hasPrefix("---\n"),
           lowercase.contains(": ")
        {
            return "yaml"
        }
        if lowercase.hasPrefix("select ")
            || lowercase.hasPrefix("with ")
            || lowercase.hasPrefix("create table ")
        {
            return "sql"
        }
        return nil
    }

    private static let commonBrackets = [
        BracketPair("(", ")"),
        BracketPair("[", "]"),
        BracketPair("{", "}"),
    ]

    private static let cBlockComment = BlockComment("/*", "*/")

    public static let plainText = LanguageDefinition(
        id: "plaintext",
        displayName: "Plain Text",
        filenameExtensions: ["txt", "text", "log", "out"]
    )

    public static let builtInDefinitions: [LanguageDefinition] = [
        LanguageDefinition(
            id: "markdown",
            displayName: "Markdown",
            exactFilenames: ["readme", "changelog", "contributing", "license"],
            filenameExtensions: ["md", "markdown", "mdown", "mkd"],
            blockComment: BlockComment("<!--", "-->"),
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "json",
            displayName: "JSON",
            exactFilenames: [".babelrc", ".eslintrc", ".prettierrc"],
            filenameExtensions: ["json", "geojson", "ipynb"],
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "jsonc",
            displayName: "JSON with Comments",
            filenameExtensions: ["jsonc"],
            lineComment: "//",
            blockComment: cBlockComment,
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "python",
            displayName: "Python",
            filenameExtensions: ["py", "pyi", "pyw"],
            shebangTokens: ["python", "python3"],
            lineComment: "#",
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "swift",
            displayName: "Swift",
            filenameExtensions: ["swift"],
            shebangTokens: ["swift"],
            lineComment: "//",
            blockComment: cBlockComment,
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "bash",
            displayName: "Shell",
            exactFilenames: [
                ".bash_profile", ".bashrc", ".profile", ".zprofile", ".zshrc",
                ".env", ".gitignore", ".gitattributes",
            ],
            filenameExtensions: ["sh", "bash", "zsh", "fish", "env"],
            shebangTokens: ["bash", "/sh", "zsh", "fish"],
            lineComment: "#",
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "yaml",
            displayName: "YAML",
            filenameExtensions: ["yaml", "yml"],
            lineComment: "#",
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "toml",
            displayName: "TOML",
            exactFilenames: ["cargo.toml", "pyproject.toml"],
            filenameExtensions: ["toml"],
            lineComment: "#",
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "xml",
            displayName: "XML",
            filenameExtensions: ["xml", "xsd", "plist", "svg"],
            blockComment: BlockComment("<!--", "-->"),
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "html",
            displayName: "HTML",
            filenameExtensions: ["html", "htm"],
            blockComment: BlockComment("<!--", "-->"),
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "css",
            displayName: "CSS",
            filenameExtensions: ["css", "scss", "sass", "less"],
            blockComment: cBlockComment,
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "javascript",
            displayName: "JavaScript",
            filenameExtensions: ["js", "mjs", "cjs"],
            shebangTokens: ["node"],
            lineComment: "//",
            blockComment: cBlockComment,
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "jsx",
            displayName: "JavaScript JSX",
            filenameExtensions: ["jsx"],
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "typescript",
            displayName: "TypeScript",
            filenameExtensions: ["ts", "mts", "cts"],
            lineComment: "//",
            blockComment: cBlockComment,
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "tsx",
            displayName: "TypeScript JSX",
            filenameExtensions: ["tsx"],
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "c",
            displayName: "C",
            filenameExtensions: ["c", "h"],
            lineComment: "//",
            blockComment: cBlockComment,
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "cpp",
            displayName: "C++",
            filenameExtensions: ["cc", "cpp", "cxx", "hh", "hpp", "hxx"],
            lineComment: "//",
            blockComment: cBlockComment,
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "objective-c",
            displayName: "Objective-C",
            filenameExtensions: ["m", "mm"],
            lineComment: "//",
            blockComment: cBlockComment,
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "go",
            displayName: "Go",
            filenameExtensions: ["go"],
            lineComment: "//",
            blockComment: cBlockComment,
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "rust",
            displayName: "Rust",
            filenameExtensions: ["rs"],
            lineComment: "//",
            blockComment: cBlockComment,
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "java",
            displayName: "Java",
            filenameExtensions: ["java"],
            lineComment: "//",
            blockComment: cBlockComment,
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "kotlin",
            displayName: "Kotlin",
            filenameExtensions: ["kt", "kts"],
            lineComment: "//",
            blockComment: cBlockComment,
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "sql",
            displayName: "SQL",
            filenameExtensions: ["sql"],
            lineComment: "--",
            blockComment: cBlockComment,
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "dockerfile",
            displayName: "Dockerfile",
            exactFilenames: ["dockerfile", "containerfile"],
            filenameExtensions: ["dockerfile"],
            lineComment: "#",
            bracketPairs: commonBrackets
        ),
        LanguageDefinition(
            id: "diff",
            displayName: "Diff",
            filenameExtensions: ["diff", "patch"],
            bracketPairs: commonBrackets
        ),
        plainText,
    ]
}
