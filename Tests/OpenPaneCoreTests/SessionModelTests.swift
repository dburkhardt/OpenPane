import Foundation
import Testing
@testable import OpenPaneCore

@Suite("Session models")
@MainActor
struct SessionModelTests {
    @Test("Editing pins a text preview and tracks dirty state")
    func editingState() throws {
        let loaded = makeLoadedFile(text: "before", filename: "sample.py")
        let session = FileSession(loadedFile: loaded)

        #expect(!session.isPinned)
        #expect(!session.isDirty)
        session.beginEditing()
        #expect(session.isPinned)
        #expect(session.isEditing)

        session.text = "after"
        #expect(session.isDirty)
        #expect(session.revision == 1)
        #expect(try String(data: session.encodedCurrentText(), encoding: .utf8) == "after")

        session.text = "before"
        #expect(!session.isDirty)
    }

    @Test("A workspace replaces only an unpinned clean preview tab")
    func previewTabs() {
        let workspace = WorkspaceSession()
        let first = FileSession(loadedFile: makeLoadedFile(text: "one", filename: "one.txt"))
        let second = FileSession(loadedFile: makeLoadedFile(text: "two", filename: "two.txt"))

        workspace.add(first)
        workspace.add(second)

        #expect(workspace.primaryTabs == [second.id])
        #expect(!workspace.sessions.keys.contains(first.id))
        #expect(workspace.selectedPrimaryTab == second.id)

        second.isPinned = true
        let third = FileSession(loadedFile: makeLoadedFile(text: "three", filename: "three.txt"))
        workspace.add(third)
        #expect(workspace.primaryTabs == [second.id, third.id])
    }

    @Test("Restoration state contains UI state but never source contents")
    func restoration() throws {
        let workspace = WorkspaceSession(
            rootURL: URL(fileURLWithPath: "/tmp/workspace"),
            rootBookmarkData: Data([1, 2, 3]),
            showAllFiles: true,
            splitOrientation: .vertical
        )
        let session = FileSession(loadedFile: makeLoadedFile(text: "private source", filename: "a.txt"))
        session.isPinned = true
        workspace.add(session)

        let state = workspace.restorationState()
        let encoded = try JSONEncoder().encode(state)
        let json = try #require(String(data: encoded, encoding: .utf8))

        #expect(!json.contains("private source"))
        #expect(state.tabs.count == 1)
        #expect(state.showAllFiles)
    }

    private func makeLoadedFile(text: String, filename: String) -> LoadedFile {
        let data = Data(text.utf8)
        let decoded = TextCodec.decode(data)!
        let classification = FileClassifier().classify(data: data, filename: filename)
        let url = URL(fileURLWithPath: "/tmp/\(filename)")
        let fingerprint = FileFingerprint.forData(data)
        return LoadedFile(
            url: url,
            fileIdentity: FileIdentity(url: url),
            data: data,
            decodedText: decoded,
            classification: classification,
            fingerprint: fingerprint,
            isBounded: false,
            totalByteCount: UInt64(data.count)
        )
    }
}
