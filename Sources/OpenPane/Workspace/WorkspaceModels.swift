import Foundation
import OpenPaneCore

enum WorkspacePaneID: String, Codable, CaseIterable, Identifiable, Sendable {
    case primary
    case secondary

    var id: Self { self }
}

enum WorkspaceSplitAxis: String, Codable, CaseIterable, Identifiable, Sendable {
    case horizontal
    case vertical

    var id: Self { self }

    var label: String {
        switch self {
        case .horizontal:
            "Side by Side"
        case .vertical:
            "Stacked"
        }
    }

    var systemImage: String {
        switch self {
        case .horizontal:
            "rectangle.split.2x1"
        case .vertical:
            "rectangle.split.1x2"
        }
    }
}

enum WorkspaceOpenBehavior: Sendable {
    case preview
    case pinned
}

struct WorkspaceTab: Identifiable, Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case id
        case url
        case isPinned
        case viewModeRawValue
        case editorState
    }

    let id: UUID
    var url: URL
    var isPinned: Bool
    var viewModeRawValue: String?
    var editorState: TextEditorState

    init(
        id: UUID = UUID(),
        url: URL,
        isPinned: Bool,
        viewModeRawValue: String? = nil,
        editorState: TextEditorState = TextEditorState()
    ) {
        self.id = id
        self.url = url
        self.isPinned = isPinned
        self.viewModeRawValue = viewModeRawValue
        self.editorState = editorState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        viewModeRawValue = try container.decodeIfPresent(
            String.self,
            forKey: .viewModeRawValue
        )
        editorState = try container.decodeIfPresent(
            TextEditorState.self,
            forKey: .editorState
        ) ?? TextEditorState()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(
            viewModeRawValue,
            forKey: .viewModeRawValue
        )
        try container.encode(editorState, forKey: .editorState)
    }

    var title: String {
        url.lastPathComponent
    }
}

struct WorkspacePaneState: Codable, Equatable, Sendable {
    var tabs: [WorkspaceTab] = []
    var selectedTabID: WorkspaceTab.ID?

    var selectedTab: WorkspaceTab? {
        guard let selectedTabID else { return nil }
        return tabs.first { $0.id == selectedTabID }
    }

    @discardableResult
    mutating func open(
        _ url: URL,
        behavior: WorkspaceOpenBehavior
    ) -> WorkspaceTab.ID {
        let canonicalURL = url.standardizedFileURL

        if let existingIndex = tabs.firstIndex(where: {
            $0.url.standardizedFileURL == canonicalURL
        }) {
            if behavior == .pinned {
                tabs[existingIndex].isPinned = true
            }
            selectedTabID = tabs[existingIndex].id
            return tabs[existingIndex].id
        }

        if behavior == .preview,
           let previewIndex = tabs.firstIndex(where: { !$0.isPinned }) {
            let replacement = WorkspaceTab(
                id: tabs[previewIndex].id,
                url: canonicalURL,
                isPinned: false,
                viewModeRawValue: nil,
                editorState: TextEditorState()
            )
            tabs[previewIndex] = replacement
            selectedTabID = replacement.id
            return replacement.id
        }

        let tab = WorkspaceTab(
            url: canonicalURL,
            isPinned: behavior == .pinned
        )
        tabs.append(tab)
        selectedTabID = tab.id
        return tab.id
    }

    mutating func pin(_ id: WorkspaceTab.ID? = nil) {
        let targetID = id ?? selectedTabID
        guard let targetID,
              let index = tabs.firstIndex(where: { $0.id == targetID }) else {
            return
        }
        tabs[index].isPinned = true
    }

    mutating func close(_ id: WorkspaceTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else {
            return
        }

        let wasSelected = selectedTabID == id
        tabs.remove(at: index)

        guard wasSelected else { return }
        if tabs.isEmpty {
            selectedTabID = nil
        } else {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
    }

    mutating func select(_ id: WorkspaceTab.ID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }
}

struct WorkspaceTreeEntry: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case directory
        case file
        case symbolicLink(isDirectory: Bool)
    }

    let url: URL
    let kind: Kind

    var id: URL { url.standardizedFileURL }

    var name: String {
        url.lastPathComponent
    }

    var isDirectory: Bool {
        switch kind {
        case .directory:
            true
        case .symbolicLink(let isDirectory):
            isDirectory
        case .file:
            false
        }
    }

    var isSymbolicLink: Bool {
        if case .symbolicLink = kind {
            return true
        }
        return false
    }
}

enum WorkspaceTreePolicy {
    static let hiddenNames: Set<String> = [
        ".DS_Store",
        ".git",
        ".hg",
        ".svn",
        "node_modules",
        ".build",
        "DerivedData",
        ".venv",
        "__pycache__"
    ]

    static func shouldShow(name: String, showAllFiles: Bool) -> Bool {
        showAllFiles || !hiddenNames.contains(name)
    }
}

struct WorkspaceLaunch: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case restore
        case folder
        case file
    }

    let kind: Kind
    let path: String?
    let bookmarkData: Data?

    static let restore = WorkspaceLaunch(
        kind: .restore,
        path: nil,
        bookmarkData: nil
    )

    static func folder(_ url: URL) -> WorkspaceLaunch {
        let canonicalURL = url.standardizedFileURL
        return WorkspaceLaunch(
            kind: .folder,
            path: canonicalURL.path,
            bookmarkData: WorkspaceSecurityBookmark.create(for: canonicalURL)
        )
    }

    static func file(_ url: URL) -> WorkspaceLaunch {
        let canonicalURL = url.standardizedFileURL
        return WorkspaceLaunch(
            kind: .file,
            path: canonicalURL.path,
            bookmarkData: WorkspaceSecurityBookmark.create(for: canonicalURL)
        )
    }

    var url: URL? {
        resolvedLocation()?.url
    }

    func resolvedLocation() -> WorkspaceResolvedBookmark? {
        WorkspaceSecurityBookmark.resolve(
            bookmarkData,
            fallbackPath: path
        )
    }
}

struct WorkspacePersistedState: Codable, Sendable {
    var rootBookmark: Data?
    var rootPathFallback: String?
    var looseFileBookmark: Data?
    var looseFilePathFallback: String?
    var additionalBookmarks: [WorkspacePersistedBookmark]?
    var primaryPane: WorkspacePaneState
    var secondaryPane: WorkspacePaneState?
    var splitAxis: WorkspaceSplitAxis
    var showAllFiles: Bool
    var expandedRelativePaths: Set<String>
}

struct WorkspacePersistedBookmark: Codable, Hashable, Sendable {
    var bookmarkData: Data?
    var pathFallback: String
}

struct WorkspaceResolvedBookmark: Sendable {
    let url: URL
    let bookmarkData: Data?
    let wasStale: Bool
}

enum WorkspaceSecurityBookmark {
    static func create(for url: URL) -> Data? {
        try? url.standardizedFileURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolve(
        _ bookmarkData: Data?,
        fallbackPath: String?
    ) -> WorkspaceResolvedBookmark? {
        if let bookmarkData {
            var isStale = false
            if let resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                let canonicalURL = resolvedURL.standardizedFileURL
                return WorkspaceResolvedBookmark(
                    url: canonicalURL,
                    bookmarkData: isStale
                        ? create(for: canonicalURL)
                        : bookmarkData,
                    wasStale: isStale
                )
            }
        }

        guard let fallbackPath else { return nil }
        let fallbackURL = URL(filePath: fallbackPath).standardizedFileURL
        return WorkspaceResolvedBookmark(
            url: fallbackURL,
            bookmarkData: create(for: fallbackURL),
            wasStale: false
        )
    }
}

struct PendingWorkspaceTabClose: Identifiable {
    let tabID: WorkspaceTab.ID
    let paneID: WorkspacePaneID
    let url: URL

    var id: WorkspaceTab.ID { tabID }
}
