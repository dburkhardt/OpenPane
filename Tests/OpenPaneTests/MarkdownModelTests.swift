import Testing
@testable import OpenPane

@Test func parsesHeadingsAndBlocks() {
    let model = MarkdownModel(
        source: """
        # Title

        Paragraph with **bold**.

        - [x] Complete

        ```swift
        let value = 1
        ```
        """
    )

    #expect(model.headings.count == 1)
    #expect(model.headings.first?.title == "Title")
    #expect(model.blocks.count == 7)
}

@Test func findsProofreadingIssues() {
    let issues = Proofreader.inspect(
        "Maybe this was completed by the team. This is is repeated."
    )

    #expect(issues.contains { $0.kind == .hedge })
    #expect(issues.contains { $0.kind == .passiveVoice })
    #expect(issues.contains { $0.kind == .repeatedWord })
}

@Test func keepsHeadingIdentifiersStableAcrossParses() {
    let source = """
    # Title

    ## Details
    """

    let first = MarkdownModel(source: source)
    let second = MarkdownModel(source: source)

    #expect(first.headings.map(\.id) == second.headings.map(\.id))
}
