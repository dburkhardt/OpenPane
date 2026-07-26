import Foundation
import OpenPaneCore
import Testing
@testable import OpenPane

@Suite("Workspace state", .serialized)
@MainActor
struct WorkspaceStateTests {
    @Test("A preview tab is replaced without disturbing pinned tabs")
    func previewReplacement() {
        var pane = WorkspacePaneState()
        let pinnedURL = URL(filePath: "/tmp/README.md")
        let firstPreviewURL = URL(filePath: "/tmp/one.json")
        let secondPreviewURL = URL(filePath: "/tmp/two.py")

        pane.open(pinnedURL, behavior: .pinned)
        pane.open(firstPreviewURL, behavior: .preview)
        let previewID = pane.selectedTabID
        pane.open(secondPreviewURL, behavior: .preview)

        #expect(pane.tabs.count == 2)
        #expect(pane.tabs.first?.url == pinnedURL)
        #expect(pane.tabs.last?.id == previewID)
        #expect(pane.tabs.last?.url == secondPreviewURL)
        #expect(pane.tabs.last?.isPinned == false)
    }

    @Test("Opening an existing preview as pinned keeps its identity")
    func pinExistingPreview() {
        var pane = WorkspacePaneState()
        let url = URL(filePath: "/tmp/example.json")

        let previewID = pane.open(url, behavior: .preview)
        let pinnedID = pane.open(url, behavior: .pinned)

        #expect(previewID == pinnedID)
        #expect(pane.tabs.count == 1)
        #expect(pane.tabs[0].isPinned)
    }

    @Test("Closing the selected tab selects its nearest neighbor")
    func closeSelection() {
        var pane = WorkspacePaneState()
        let firstID = pane.open(
            URL(filePath: "/tmp/first.md"),
            behavior: .pinned
        )
        let secondID = pane.open(
            URL(filePath: "/tmp/second.md"),
            behavior: .pinned
        )

        pane.close(secondID)

        #expect(pane.selectedTabID == firstID)
        #expect(pane.tabs.count == 1)
    }

    @Test("The workspace never creates more than two editor groups")
    func atMostTwoEditorGroups() {
        let store = WorkspaceStore(launch: .restore)

        store.createSplit(axis: .horizontal)
        let originalSecondary = store.secondaryPane
        store.createSplit(axis: .vertical)

        #expect(store.secondaryPane != nil)
        #expect(store.secondaryPane == originalSecondary)
        #expect(store.splitAxis == .vertical)
    }

    @Test("Both editor groups share one runtime file session")
    func sharedFileSession() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "OpenPaneWorkspaceTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appending(path: "shared.json")
        try Data(#"{"shared":true}"#.utf8).write(to: fileURL)

        let registry = WorkspaceDocumentRegistry()
        let primary = try await registry.load(fileURL, isPinned: false)
        let secondary = try await registry.load(fileURL, isPinned: true)

        #expect(primary === secondary)
        #expect(primary.isPinned)
    }

    @Test("Quick Open favors exact file-name matches")
    func quickOpenRanking() {
        let exact = URL(filePath: "/project/src/model.py")
        let pathOnly = URL(filePath: "/project/model.py/examples/demo.txt")
        let partial = URL(filePath: "/project/src/model_helper.py")

        let results = QuickOpenMatcher.matches(
            query: "model.py",
            files: [pathOnly, partial, exact],
            relativePath: { url in
                String(url.path.dropFirst("/project/".count))
            }
        )

        #expect(results.first == exact)
        #expect(results.contains(pathOnly))
    }

    @Test("Useful dotfiles remain visible while generated folders stay hidden")
    func hiddenFilePolicy() {
        #expect(
            WorkspaceTreePolicy.shouldShow(
                name: ".env",
                showAllFiles: false
            )
        )
        #expect(
            WorkspaceTreePolicy.shouldShow(
                name: ".github",
                showAllFiles: false
            )
        )
        #expect(
            !WorkspaceTreePolicy.shouldShow(
                name: ".DS_Store",
                showAllFiles: false
            )
        )
        #expect(
            !WorkspaceTreePolicy.shouldShow(
                name: "node_modules",
                showAllFiles: false
            )
        )
        #expect(
            WorkspaceTreePolicy.shouldShow(
                name: ".DS_Store",
                showAllFiles: true
            )
        )
    }

    @Test("A loose-file launch retains a restorable location")
    func looseFileLaunchRoundTrip() throws {
        let fileURL = FileManager.default.temporaryDirectory.appending(
            path: "OpenPaneLaunch-\(UUID().uuidString).txt"
        )
        try Data("launch".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let encoded = try JSONEncoder().encode(WorkspaceLaunch.file(fileURL))
        let decoded = try JSONDecoder().decode(
            WorkspaceLaunch.self,
            from: encoded
        )

        #expect(decoded.kind == .file)
        #expect(decoded.path == fileURL.standardizedFileURL.path)
        #expect(
            decoded.resolvedLocation()?.url.standardizedFileURL
                == fileURL.standardizedFileURL
        )
    }

    @Test("Only a blank window accepts an external loose-file open")
    func blankWindowRoutingState() throws {
        let fileURL = FileManager.default.temporaryDirectory.appending(
            path: "OpenPaneExternal-\(UUID().uuidString).txt"
        )
        try Data("external".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = WorkspaceStore(launch: .restore)
        #expect(store.canAcceptExternalOpenInCurrentWindow)

        store.openLooseFile(fileURL)

        #expect(!store.canAcceptExternalOpenInCurrentWindow)
    }

    @Test("Loose files are included in workspace restoration")
    func looseFilePersistence() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.data(
            forKey: WorkspaceStore.persistedStateKey
        )
        defer {
            if let previous {
                defaults.set(
                    previous,
                    forKey: WorkspaceStore.persistedStateKey
                )
            } else {
                defaults.removeObject(
                    forKey: WorkspaceStore.persistedStateKey
                )
            }
        }

        let fileURL = FileManager.default.temporaryDirectory.appending(
            path: "OpenPaneLoose-\(UUID().uuidString).json"
        )
        try Data("{}".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = WorkspaceStore(launch: .restore)
        store.openLooseFile(fileURL)

        let data = try #require(
            defaults.data(forKey: WorkspaceStore.persistedStateKey)
        )
        let state = try JSONDecoder().decode(
            WorkspacePersistedState.self,
            from: data
        )
        #expect(state.rootPathFallback == nil)
        #expect(
            state.looseFilePathFallback
                == fileURL.standardizedFileURL.path
        )
        #expect(state.primaryPane.selectedTab?.url == fileURL)
    }

    @Test("Existing folder restoration data remains decodable")
    func legacyWorkspaceStateDecoding() throws {
        let state = WorkspacePersistedState(
            rootBookmark: nil,
            rootPathFallback: "/tmp/project",
            looseFileBookmark: nil,
            looseFilePathFallback: nil,
            additionalBookmarks: nil,
            primaryPane: WorkspacePaneState(),
            secondaryPane: nil,
            splitAxis: .horizontal,
            showAllFiles: false,
            expandedRelativePaths: [""]
        )
        let currentData = try JSONEncoder().encode(state)
        var object = try #require(
            JSONSerialization.jsonObject(with: currentData)
                as? [String: Any]
        )
        object["looseFileBookmark"] = nil
        object["looseFilePathFallback"] = nil
        object["additionalBookmarks"] = nil
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            WorkspacePersistedState.self,
            from: legacyData
        )
        #expect(decoded.rootPathFallback == "/tmp/project")
        #expect(decoded.looseFilePathFallback == nil)
        #expect(decoded.additionalBookmarks == nil)
    }

    @Test("Closing recovery is flushed and explicit discard removes it")
    func closeRecoveryLifecycle() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "OpenPaneCloseRecovery-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let recovery = directory.appending(
            path: "Recovery",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appending(path: "notes.md")
        try Data("# Notes\n".utf8).write(to: fileURL)
        let registry = WorkspaceDocumentRegistry(
            fileIO: FileIOActor(
                configuration: FileIOConfiguration(
                    recoveryDirectory: recovery
                )
            )
        )
        let session = try await registry.load(fileURL, isPinned: true)
        session.beginEditing()
        session.text = "# Changed\n"

        try await registry.flushRecoverySnapshots()
        let snapshot = recovery
            .appending(path: session.id.uuidString)
            .appendingPathExtension("txt")
        #expect(FileManager.default.fileExists(atPath: snapshot.path))
        #expect(
            try String(contentsOf: snapshot, encoding: .utf8)
                .contains("# Changed")
        )

        try await registry.discardAllDirtySessionsForClosing()
        #expect(!FileManager.default.fileExists(atPath: snapshot.path))
        #expect(!registry.hasDirtySessions)
    }

    @Test("The same Markdown file keeps independent pane view modes")
    func paneLocalViewModes() {
        let url = URL(filePath: "/tmp/README.md")
        var primary = WorkspacePaneState()
        var secondary = WorkspacePaneState()
        let primaryID = primary.open(url, behavior: .pinned)
        let secondaryID = secondary.open(url, behavior: .pinned)
        primary.tabs[0].viewModeRawValue = FileViewMode.source.rawValue
        secondary.tabs[0].viewModeRawValue = FileViewMode.reader.rawValue
        primary.tabs[0].editorState = TextEditorState(
            cursorLocation: 42,
            selectionLength: 3,
            verticalScrollOffset: 120,
            horizontalScrollOffset: 4
        )
        secondary.tabs[0].editorState = TextEditorState(
            cursorLocation: 7,
            verticalScrollOffset: 20
        )

        #expect(primaryID != secondaryID)
        #expect(
            primary.selectedTab?.viewModeRawValue
                == FileViewMode.source.rawValue
        )
        #expect(
            secondary.selectedTab?.viewModeRawValue
                == FileViewMode.reader.rawValue
        )
        #expect(primary.selectedTab?.editorState.cursorLocation == 42)
        #expect(primary.selectedTab?.editorState.selectionLength == 3)
        #expect(secondary.selectedTab?.editorState.cursorLocation == 7)
        #expect(
            primary.selectedTab?.editorState.verticalScrollOffset == 120
        )
    }

    @Test("Activating an open file selects its existing tab")
    func activateExistingTab() {
        let defaults = UserDefaults.standard
        let previous = defaults.data(
            forKey: WorkspaceStore.persistedStateKey
        )
        defer {
            if let previous {
                defaults.set(
                    previous,
                    forKey: WorkspaceStore.persistedStateKey
                )
            } else {
                defaults.removeObject(
                    forKey: WorkspaceStore.persistedStateKey
                )
            }
        }
        let store = WorkspaceStore(launch: .restore)
        let first = URL(filePath: "/tmp/first.md")
        let second = URL(filePath: "/tmp/second.json")
        store.open(first, behavior: .pinned, in: .primary)
        store.open(second, behavior: .pinned, in: .primary)

        #expect(store.selectedURL == second)
        #expect(store.activateOpenFile(first))
        #expect(store.selectedURL == first)
        #expect(store.primaryPane.tabs.count == 2)
    }

    @Test("Cursor and scroll state persist with the selected tab")
    func editorStatePersistence() async throws {
        let defaults = UserDefaults.standard
        let previous = defaults.data(
            forKey: WorkspaceStore.persistedStateKey
        )
        defer {
            if let previous {
                defaults.set(
                    previous,
                    forKey: WorkspaceStore.persistedStateKey
                )
            } else {
                defaults.removeObject(
                    forKey: WorkspaceStore.persistedStateKey
                )
            }
        }

        let fileURL = FileManager.default.temporaryDirectory.appending(
            path: "OpenPaneEditorState-\(UUID().uuidString).json"
        )
        try Data("{}".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = WorkspaceStore(launch: .restore)
        store.openLooseFile(fileURL)
        let tabID = try #require(store.primaryPane.selectedTabID)
        let expected = TextEditorState(
            cursorLocation: 17,
            selectionLength: 2,
            verticalScrollOffset: 88,
            horizontalScrollOffset: 6
        )
        store.updateEditorState(
            expected,
            for: tabID,
            in: .primary
        )
        try await Task.sleep(for: .milliseconds(350))

        let data = try #require(
            defaults.data(forKey: WorkspaceStore.persistedStateKey)
        )
        let state = try JSONDecoder().decode(
            WorkspacePersistedState.self,
            from: data
        )
        #expect(state.primaryPane.selectedTab?.editorState == expected)
    }

    @Test(
        "Indentation status reflects source",
        arguments: [
            ("root:\n  child: true\n", "Spaces: 2"),
            ("def f():\n    return 1\n", "Spaces: 4"),
            ("root:\n\tchild\n", "Tabs"),
            ("plain text\n", "No indentation"),
        ]
    )
    func indentationStatus(source: String, expected: String) {
        #expect(TextIndentationDetector.description(for: source) == expected)
    }
}
