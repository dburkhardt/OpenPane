import Foundation
import Testing
@testable import OpenPaneCore

@Suite("Synthetic workspace fixtures")
struct SyntheticFixtureTests {
    private let classifier = FileClassifier()

    @Test(
        "Checked-in fixtures classify by filename and signature",
        arguments: [
            ("README.md", FileKind.markdown),
            ("settings.json", .text(languageID: "json")),
            ("script.py", .text(languageID: "python")),
            ("Dockerfile", .text(languageID: "dockerfile")),
            (".env", .text(languageID: "bash")),
            ("renamed-pdf.bin", .pdf),
        ]
    )
    func classifiesFixture(filename: String, expected: FileKind) throws {
        let url = fixtureDirectory.appendingPathComponent(filename)
        let data = try Data(contentsOf: url)

        #expect(
            classifier.classify(
                data: data,
                filename: filename
            ).kind == expected
        )
    }

    private var fixtureDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/workspace", isDirectory: true)
    }
}
