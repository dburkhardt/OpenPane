import AppKit
import Markdown
import SwiftUI

struct MarkdownListItemModel: Identifiable {
    let id = UUID()
    let blocks: [MarkdownRenderBlock]
    let checkbox: Bool?
}

struct MarkdownImageModel: Identifiable {
    let id = UUID()
    let url: URL
    let alternativeText: String
}

struct MarkdownTableModel {
    let headers: [AttributedString]
    let rows: [[AttributedString]]
    let alignments: [Markdown.Table.ColumnAlignment?]
}

indirect enum MarkdownRenderBlock: Identifiable {
    case heading(
        UUID,
        level: Int,
        content: AttributedString,
        title: String,
        anchor: String
    )
    case paragraph(UUID, content: AttributedString, images: [MarkdownImageModel])
    case quote(UUID, blocks: [MarkdownRenderBlock])
    case list(
        UUID,
        ordered: Bool,
        start: Int,
        items: [MarkdownListItemModel]
    )
    case code(UUID, language: String?, source: String)
    case table(UUID, MarkdownTableModel)
    case divider(UUID)
    case rawHTML(UUID, String)

    var id: UUID {
        switch self {
        case .heading(let id, _, _, _, _),
             .paragraph(let id, _, _),
             .quote(let id, _),
             .list(let id, _, _, _),
             .code(let id, _, _),
             .table(let id, _),
             .divider(let id),
             .rawHTML(let id, _):
            id
        }
    }
}

struct MarkdownHeadingModel: Identifiable {
    let id: UUID
    let level: Int
    let title: String
    let anchor: String
}

enum MarkdownLinkAction: Equatable {
    case openFile(URL)
    case scrollToFragment(String)
    case blocked
}

enum MarkdownLinkPolicy {
    /// Markdown is an offline document format in OpenPane. Only a fragment in
    /// the current document or a local file is actionable; web, data, mail,
    /// application, and other custom schemes remain inert.
    static func action(for destination: URL, baseURL: URL?) -> MarkdownLinkAction {
        if destination.scheme != nil {
            guard destination.isFileURL else { return .blocked }
            return .openFile(destination.standardizedFileURLPreservingFragment)
        }

        let relativePath = destination.relativePath.removingPercentEncoding
            ?? destination.relativePath
        if relativePath.isEmpty, let fragment = decodedFragment(destination.fragment) {
            return .scrollToFragment(fragment)
        }

        guard let baseURL, !relativePath.isEmpty else { return .blocked }
        let directory = baseURL.hasDirectoryPath
            ? baseURL
            : baseURL.deletingLastPathComponent()
        let fileURL = URL(
            fileURLWithPath: relativePath,
            relativeTo: directory
        ).standardizedFileURL
        return .openFile(fileURL.addingFragment(destination.fragment))
    }

    static func decodedFragment(_ fragment: String?) -> String? {
        guard let fragment, !fragment.isEmpty else { return nil }
        return fragment.removingPercentEncoding ?? fragment
    }
}

struct MarkdownReaderView: View {
    let source: String
    let baseURL: URL?
    let onOpenURL: (URL) -> Void

    @AppStorage("reader.readingWidth") private var readingWidth = 780.0
    @AppStorage("reader.fontSize") private var fontSize = 16.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blocks: [MarkdownRenderBlock]

    init(
        source: String,
        baseURL: URL?,
        onOpenURL: @escaping (URL) -> Void = { _ in }
    ) {
        self.source = source
        self.baseURL = baseURL
        self.onOpenURL = onOpenURL
        _blocks = State(
            initialValue: MarkdownReaderParser.parse(source, baseURL: baseURL)
        )
    }

    private var headings: [MarkdownHeadingModel] {
        collectHeadings(in: blocks)
    }

    private func collectHeadings(
        in blocks: [MarkdownRenderBlock]
    ) -> [MarkdownHeadingModel] {
        blocks.flatMap { block -> [MarkdownHeadingModel] in
            switch block {
            case let .heading(id, level, _, title, anchor):
                [
                    MarkdownHeadingModel(
                        id: id,
                        level: level,
                        title: title,
                        anchor: anchor
                    )
                ]
            case .quote(_, let nested):
                collectHeadings(in: nested)
            case .list(_, _, _, let items):
                items.flatMap { collectHeadings(in: $0.blocks) }
            default:
                []
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if !headings.isEmpty {
                    HStack {
                        Menu {
                            ForEach(headings) { heading in
                                Button {
                                    scrollTo(
                                        heading.id,
                                        using: proxy
                                    )
                                } label: {
                                    Text(
                                        String(repeating: "  ", count: max(0, heading.level - 1))
                                            + heading.title
                                    )
                                }
                            }
                        } label: {
                            Label("Outline", systemImage: "list.bullet.indent")
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(.bar)
                    Divider()
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 13) {
                        ForEach(blocks) { block in
                            blockView(block)
                                .id(block.id)
                        }
                    }
                    .frame(maxWidth: readingWidth, alignment: .leading)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 30)
                    .frame(maxWidth: .infinity)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
            .environment(
                \.openURL,
                OpenURLAction { url in
                    switch MarkdownLinkPolicy.action(for: url, baseURL: baseURL) {
                    case .openFile(let destination):
                        onOpenURL(destination)
                    case .scrollToFragment(let fragment):
                        if let heading = headings.first(where: {
                            $0.anchor.caseInsensitiveCompare(fragment) == .orderedSame
                        }) {
                            scrollTo(heading.id, using: proxy)
                        }
                    case .blocked:
                        break
                    }
                    return .handled
                }
            )
        }
        .task(id: MarkdownRefreshKey(source: source, baseURL: baseURL)) {
            blocks = MarkdownReaderParser.parse(source, baseURL: baseURL)
        }
    }

    private func scrollTo(
        _ id: MarkdownHeadingModel.ID,
        using proxy: ScrollViewProxy
    ) {
        if reduceMotion {
            proxy.scrollTo(id, anchor: .top)
        } else {
            withAnimation(.easeInOut(duration: 0.15)) {
                proxy.scrollTo(id, anchor: .top)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownRenderBlock) -> some View {
        switch block {
        case .heading(_, let level, let content, _, _):
            Text(content)
                .font(headingFont(level))
                .fontWeight(level <= 2 ? .bold : .semibold)
                .textSelection(.enabled)
                .padding(.top, level == 1 ? 12 : 7)
                .accessibilityAddTraits(.isHeader)

        case .paragraph(_, let content, let images):
            VStack(alignment: .leading, spacing: 10) {
                if !content.characters.isEmpty {
                    Text(content)
                        .font(.system(size: fontSize))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                }
                ForEach(images) { image in
                    LocalMarkdownImageView(image: image)
                }
            }

        case .quote(_, let blocks):
            HStack(alignment: .top, spacing: 13) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.secondary)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(blocks) { nestedBlock in
                        AnyView(blockView(nestedBlock))
                    }
                }
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

        case .list(_, let ordered, let start, let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .top, spacing: 9) {
                        if let checkbox = item.checkbox {
                            Image(systemName: checkbox ? "checkmark.square.fill" : "square")
                                .foregroundStyle(checkbox ? Color.accentColor : Color.secondary)
                                .accessibilityLabel(checkbox ? "Completed" : "Not completed")
                        } else {
                            Text(ordered ? "\(start + index)." : "•")
                                .fontWeight(.semibold)
                                .frame(minWidth: ordered ? 24 : 12, alignment: .trailing)
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(item.blocks) { nestedBlock in
                                AnyView(blockView(nestedBlock))
                            }
                        }
                    }
                }
            }
            .padding(.leading, 5)

        case .code(_, let language, let source):
            MarkdownCodeBlockView(language: language, source: source, fontSize: fontSize)

        case .table(_, let table):
            MarkdownTableView(table: table, fontSize: fontSize)

        case .divider:
            Divider()
                .padding(.vertical, 8)

        case .rawHTML(_, let html):
            VStack(alignment: .leading, spacing: 6) {
                Text("HTML (not executed)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    Text(html)
                        .font(.system(size: max(11, fontSize - 2), design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .system(size: fontSize * 2.05)
        case 2: .system(size: fontSize * 1.6)
        case 3: .system(size: fontSize * 1.3)
        default: .system(size: fontSize * 1.08)
        }
    }

}

private extension URL {
    var standardizedFileURLPreservingFragment: URL {
        standardizedFileURL.addingFragment(fragment)
    }

    func addingFragment(_ fragment: String?) -> URL {
        guard let fragment, !fragment.isEmpty else { return self }
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.fragment = fragment
        return components?.url ?? self
    }
}

private struct MarkdownRefreshKey: Equatable {
    let source: String
    let baseURL: URL?
}

private struct LocalMarkdownImageView: View {
    let image: MarkdownImageModel

    var body: some View {
        if let nsImage = NSImage(contentsOf: image.url) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(
                    image.alternativeText.isEmpty ? image.url.lastPathComponent : image.alternativeText
                )
        } else {
            Label(
                image.alternativeText.isEmpty
                    ? "Image unavailable"
                    : image.alternativeText,
                systemImage: "photo.badge.exclamationmark"
            )
            .foregroundStyle(.secondary)
        }
    }
}

private struct MarkdownCodeBlockView: View {
    let language: String?
    let source: String
    let fontSize: CGFloat

    private var height: CGFloat {
        let lineCount = max(1, source.components(separatedBy: .newlines).count)
        return min(380, max(54, CGFloat(lineCount) * (fontSize + 4) + 22))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let language, !language.isEmpty {
                Text(language.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Code language \(language)")
            }
            NativeTextEditor(
                text: .constant(source),
                languageID: language ?? "plaintext",
                isEditable: false,
                wordWrap: false,
                fontSize: max(11, fontSize - 2),
                showsLineNumbers: source.contains("\n")
            )
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .padding(10)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct MarkdownTableView: View {
    let table: MarkdownTableModel
    let fontSize: CGFloat

    var body: some View {
        ScrollView(.horizontal) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                if !table.headers.isEmpty {
                    GridRow {
                        ForEach(Array(table.headers.enumerated()), id: \.offset) { _, header in
                            Text(header)
                                .font(.system(size: fontSize, weight: .semibold))
                                .textSelection(.enabled)
                                .frame(minWidth: 100, maxWidth: 280, alignment: .leading)
                                .padding(9)
                                .background(.quaternary.opacity(0.55))
                        }
                    }
                }

                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                    Divider()
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .font(.system(size: fontSize))
                                .textSelection(.enabled)
                                .frame(minWidth: 100, maxWidth: 280, alignment: .leading)
                                .padding(9)
                                .background(
                                    rowIndex.isMultiple(of: 2)
                                        ? Color.clear
                                        : Color.secondary.opacity(0.04)
                                )
                        }
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Markdown table")
    }
}

enum MarkdownReaderParser {
    static func parse(_ source: String, baseURL: URL?) -> [MarkdownRenderBlock] {
        let document = Document(parsing: source, source: baseURL)
        var anchors: [String: Int] = [:]
        return renderBlocks(
            document.children,
            baseURL: baseURL,
            anchors: &anchors
        )
    }

    private static func renderBlocks(
        _ markups: MarkupChildren,
        baseURL: URL?,
        anchors: inout [String: Int]
    ) -> [MarkdownRenderBlock] {
        var output: [MarkdownRenderBlock] = []
        for markup in markups {
            if let heading = markup as? Heading {
                let title = heading.plainText
                output.append(.heading(
                    UUID(),
                    level: heading.level,
                    content: inlineAttributedString(from: heading),
                    title: title,
                    anchor: uniqueAnchor(for: title, anchors: &anchors)
                ))
                continue
            }
            if let paragraph = markup as? Paragraph {
                output.append(.paragraph(
                    UUID(),
                    content: inlineAttributedString(from: paragraph),
                    images: localImages(in: paragraph, baseURL: baseURL)
                ))
                continue
            }
            if let quote = markup as? BlockQuote {
                output.append(.quote(
                    UUID(),
                    blocks: renderBlocks(
                        quote.children,
                        baseURL: baseURL,
                        anchors: &anchors
                    )
                ))
                continue
            }
            if let list = markup as? UnorderedList {
                output.append(.list(
                    UUID(),
                    ordered: false,
                    start: 1,
                    items: list.listItems.map {
                        listItem($0, baseURL: baseURL, anchors: &anchors)
                    }
                ))
                continue
            }
            if let list = markup as? OrderedList {
                output.append(.list(
                    UUID(),
                    ordered: true,
                    start: Int(list.startIndex),
                    items: list.listItems.map {
                        listItem($0, baseURL: baseURL, anchors: &anchors)
                    }
                ))
                continue
            }
            if let code = markup as? CodeBlock {
                output.append(
                    .code(UUID(), language: code.language, source: code.code)
                )
                continue
            }
            if let table = markup as? Markdown.Table {
                let headers = table.head.cells.map {
                    attributedString(from: $0.plainText)
                }
                let rows = table.body.rows.map { row in
                    Array(
                        row.cells.map {
                            attributedString(from: $0.plainText)
                        }
                    )
                }
                output.append(.table(
                    UUID(),
                    MarkdownTableModel(
                        headers: Array(headers),
                        rows: Array(rows),
                        alignments: table.columnAlignments
                    )
                ))
                continue
            }
            if markup is ThematicBreak {
                output.append(.divider(UUID()))
                continue
            }
            if let html = markup as? HTMLBlock {
                output.append(.rawHTML(UUID(), html.rawHTML))
                continue
            }
            // Preserve block containers introduced by newer swift-markdown
            // versions even before OpenPane gives them specialized chrome.
            output.append(
                contentsOf: renderBlocks(
                    markup.children,
                    baseURL: baseURL,
                    anchors: &anchors
                )
            )
        }
        return output
    }

    private static func listItem(
        _ item: ListItem,
        baseURL: URL?,
        anchors: inout [String: Int]
    ) -> MarkdownListItemModel {
        let checkbox: Bool?
        switch item.checkbox {
        case .checked?: checkbox = true
        case .unchecked?: checkbox = false
        case nil: checkbox = nil
        }
        return MarkdownListItemModel(
            blocks: renderBlocks(
                item.children,
                baseURL: baseURL,
                anchors: &anchors
            ),
            checkbox: checkbox
        )
    }

    static func headingAnchor(_ title: String) -> String {
        var result = ""
        var needsSeparator = false

        for scalar in title.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar)
                || scalar == "_"
                || scalar == "-" {
                if needsSeparator, !result.isEmpty, !result.hasSuffix("-") {
                    result.append("-")
                }
                result.unicodeScalars.append(scalar)
                needsSeparator = false
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                needsSeparator = true
            }
        }

        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func uniqueAnchor(
        for title: String,
        anchors: inout [String: Int]
    ) -> String {
        let base = headingAnchor(title)
        let safeBase = base.isEmpty ? "section" : base
        let occurrence = anchors[safeBase, default: 0]
        anchors[safeBase] = occurrence + 1
        return occurrence == 0 ? safeBase : "\(safeBase)-\(occurrence)"
    }

    private static func inlineAttributedString(
        from markup: some InlineContainer
    ) -> AttributedString {
        attributedString(from: markup.format())
    }

    private static func attributedString(from source: String) -> AttributedString {
        let value = source.trimmingCharacters(in: .newlines)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: value, options: options))
            ?? AttributedString(value)
    }

    private static func localImages(
        in markup: Markup,
        baseURL: URL?
    ) -> [MarkdownImageModel] {
        var images: [MarkdownImageModel] = []
        collectImages(in: markup, baseURL: baseURL, output: &images)
        return images
    }

    private static func collectImages(
        in markup: Markup,
        baseURL: URL?,
        output: inout [MarkdownImageModel]
    ) {
        if let image = markup as? Markdown.Image,
           let source = image.source,
           let url = localURL(source, baseURL: baseURL) {
            output.append(
                MarkdownImageModel(
                    url: url,
                    alternativeText: image.plainText
                )
            )
        }
        for child in markup.children {
            collectImages(in: child, baseURL: baseURL, output: &output)
        }
    }

    private static func localURL(_ source: String, baseURL: URL?) -> URL? {
        if let absolute = URL(string: source), absolute.scheme != nil {
            return absolute.isFileURL ? absolute.standardizedFileURL : nil
        }
        guard let baseURL else { return nil }
        let directory = baseURL.hasDirectoryPath
            ? baseURL
            : baseURL.deletingLastPathComponent()
        return URL(
            fileURLWithPath: source.removingPercentEncoding ?? source,
            relativeTo: directory
        ).standardizedFileURL
    }
}
