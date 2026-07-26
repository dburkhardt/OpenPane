import Foundation
import Testing
@testable import OpenPane

@Suite("Markdown reader")
struct MarkdownReaderTests {
    @Test("Only fragments and local files are actionable")
    func safeLinkPolicy() {
        let document = URL(filePath: "/tmp/OpenPane/README.md")

        #expect(
            MarkdownLinkPolicy.action(
                for: URL(string: "#install")!,
                baseURL: document
            ) == .scrollToFragment("install")
        )
        #expect(
            MarkdownLinkPolicy.action(
                for: URL(string: "guide/setup.md#run")!,
                baseURL: document
            ) == .openFile(
                URL(filePath: "/tmp/OpenPane/guide/setup.md")
                    .withFragment("run")
            )
        )
        #expect(
            MarkdownLinkPolicy.action(
                for: URL(string: "https://example.com/tracker")!,
                baseURL: document
            ) == .blocked
        )
        #expect(
            MarkdownLinkPolicy.action(
                for: URL(string: "mailto:person@example.com")!,
                baseURL: document
            ) == .blocked
        )
        #expect(
            MarkdownLinkPolicy.action(
                for: URL(string: "openpane-test:run")!,
                baseURL: document
            ) == .blocked
        )
    }

    @Test("GFM blocks retain nested lists quotes tasks and local images")
    func recursiveGFMFixture() {
        let document = URL(filePath: "/tmp/OpenPane/README.md")
        let source = """
        # Overview

        > Quoted introduction
        >
        > - Parent
        >   - Nested
        >
        > ![Local plot](images/plot.png)
        > ![Remote pixel](https://example.com/pixel.png)

        - [x] Complete
          1. First
          2. Second

        | Name | Value |
        | --- | ---: |
        | café | 🚀 |
        """

        let blocks = MarkdownReaderParser.parse(source, baseURL: document)

        guard case .heading(_, _, _, _, let anchor) = blocks.first else {
            Issue.record("Expected a heading")
            return
        }
        #expect(anchor == "overview")
        #expect(blocks.contains { if case .table = $0 { true } else { false } })

        guard let quote = blocks.first(where: {
            if case .quote = $0 { true } else { false }
        }), case .quote(_, let quoteBlocks) = quote else {
            Issue.record("Expected a recursive block quote")
            return
        }
        #expect(containsNestedList(in: quoteBlocks))

        let images = collectImages(in: blocks)
        #expect(images.count == 1)
        #expect(images[0].alternativeText == "Local plot")
        #expect(images[0].url == URL(filePath: "/tmp/OpenPane/images/plot.png"))

        let taskItems = collectListItems(in: blocks).filter { $0.checkbox != nil }
        #expect(taskItems.count == 1)
        #expect(taskItems[0].checkbox == true)
        #expect(
            taskItems[0].blocks.contains {
                if case .list = $0 { true } else { false }
            }
        )
    }

    @Test("Heading fragments are stable and duplicates are unique")
    func headingAnchors() {
        let blocks = MarkdownReaderParser.parse(
            "# Café & Launch\n\n## Café & Launch\n\n# 🚀",
            baseURL: nil
        )
        let anchors = blocks.compactMap { block -> String? in
            guard case .heading(_, _, _, _, let anchor) = block else {
                return nil
            }
            return anchor
        }

        #expect(anchors == ["café-launch", "café-launch-1", "section"])
        #expect(MarkdownReaderParser.headingAnchor("One   Two") == "one-two")
    }

    private func containsNestedList(in blocks: [MarkdownRenderBlock]) -> Bool {
        blocks.contains { block in
            guard case .list(_, _, _, let items) = block else { return false }
            return items.contains { item in
                item.blocks.contains {
                    if case .list = $0 { true } else { false }
                }
            }
        }
    }

    private func collectImages(
        in blocks: [MarkdownRenderBlock]
    ) -> [MarkdownImageModel] {
        blocks.flatMap { block -> [MarkdownImageModel] in
            switch block {
            case .paragraph(_, _, let images):
                images
            case .quote(_, let nested):
                collectImages(in: nested)
            case .list(_, _, _, let items):
                items.flatMap { collectImages(in: $0.blocks) }
            default:
                []
            }
        }
    }

    private func collectListItems(
        in blocks: [MarkdownRenderBlock]
    ) -> [MarkdownListItemModel] {
        blocks.flatMap { block -> [MarkdownListItemModel] in
            switch block {
            case .quote(_, let nested):
                collectListItems(in: nested)
            case .list(_, _, _, let items):
                items + items.flatMap { collectListItems(in: $0.blocks) }
            default:
                []
            }
        }
    }
}

private extension URL {
    func withFragment(_ fragment: String) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.fragment = fragment
        return components?.url ?? self
    }
}
