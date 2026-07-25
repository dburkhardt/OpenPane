import SwiftUI

struct MarkdownPreview: View {
    let model: MarkdownModel
    @Binding var selectedHeading: String?

    @AppStorage("readingWidth") private var readingWidth = 760.0
    @AppStorage("baseFontSize") private var baseFontSize = 16.0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.blocks) { block in
                        blockView(block)
                    }
                }
                .frame(maxWidth: readingWidth, alignment: .leading)
                .padding(.horizontal, 36)
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: selectedHeading) { _, value in
                guard let value else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(value, anchor: .top)
                }
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownModel.Block) -> some View {
        switch block {
        case .heading(let heading):
            inlineText(heading.title)
                .font(headingFont(level: heading.level))
                .fontWeight(heading.level <= 2 ? .bold : .semibold)
                .padding(.top, heading.level == 1 ? 12 : 8)
                .id(heading.id)

        case .paragraph(_, let text):
            inlineText(text)
                .font(.system(size: baseFontSize))
                .lineSpacing(5)
                .textSelection(.enabled)

        case .quote(_, let text):
            HStack(spacing: 12) {
                Rectangle()
                    .fill(.secondary)
                    .frame(width: 3)
                inlineText(text)
                    .foregroundStyle(.secondary)
                    .italic()
            }
            .padding(.vertical, 4)

        case .bullet(_, let text, let checked):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                if let checked {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checked ? Color.accentColor : Color.secondary)
                } else {
                    Text("•")
                        .fontWeight(.bold)
                }
                inlineText(text)
            }
            .padding(.leading, 8)

        case .code(_, let language, let source):
            VStack(alignment: .leading, spacing: 7) {
                if let language {
                    Text(language.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    Text(source)
                        .font(.system(size: max(12, baseFontSize - 2), design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 9))

        case .divider:
            Divider().padding(.vertical, 8)

        case .blank:
            Spacer().frame(height: 2)
        }
    }

    private func inlineText(_ source: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        let attributed = (try? AttributedString(markdown: source, options: options))
            ?? AttributedString(source)
        return Text(attributed)
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: .system(size: baseFontSize * 2.1)
        case 2: .system(size: baseFontSize * 1.65)
        case 3: .system(size: baseFontSize * 1.3)
        default: .system(size: baseFontSize * 1.1)
        }
    }
}
