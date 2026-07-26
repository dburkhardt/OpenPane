import AppKit
import Combine
import Foundation
import OpenPaneCore

@MainActor
final class WorkspaceStore: ObservableObject, Identifiable {
    static let persistedStateKey = "OpenPane.Workspace.LastState.v1"

    let id = UUID()
    let launch: WorkspaceLaunch
    let documents = WorkspaceDocumentRegistry()

    @Published private(set) var rootURL: URL?
    @Published private(set) var childrenByDirectory: [URL: [WorkspaceTreeEntry]] = [:]
    @Published private(set) var loadingDirectories: Set<URL> = []
    @Published private(set) var quickOpenFiles: [URL] = []
    @Published private(set) var isIndexingQuickOpen = false
    @Published var primaryPane = WorkspacePaneState()
    @Published var secondaryPane: WorkspacePaneState?
    @Published var splitAxis = WorkspaceSplitAxis.horizontal {
        didSet {
            guard oldValue != splitAxis, !isRestoringPersistedState else {
                return
            }
            persist()
        }
    }
    @Published var activePane = WorkspacePaneID.primary
    @Published var showAllFiles = false {
        didSet {
            guard oldValue != showAllFiles else { return }
            guard !isRestoringPersistedState else { return }
            childrenByDirectory.removeAll()
            if let rootURL {
                loadDirectory(rootURL, refresh: true)
                rebuildQuickOpenIndex()
            }
            persist()
        }
    }
    @Published var expandedDirectories: Set<URL> = []
    @Published var operationError: String?
    @Published var pendingTabClose: PendingWorkspaceTabClose?
    @Published private(set) var pendingRecoverySnapshotURLs: [URL] = []

    private var hasStarted = false
    private var isRestoringPersistedState = false
    private var securityScope: SecurityScopeAccess?
    private var rootBookmarkData: Data?
    private var looseFileBookmarkData: Data?
    private var additionalSecurityScopes: [URL: SecurityScopeAccess] = [:]
    private var additionalBookmarkData: [URL: Data] = [:]
    private var quickOpenTask: Task<Void, Never>?
    private var statePersistTask: Task<Void, Never>?

    init(launch: WorkspaceLaunch = .restore) {
        self.launch = launch
    }

    deinit {
        quickOpenTask?.cancel()
        statePersistTask?.cancel()
    }

    var displayName: String {
        if let rootURL {
            return rootURL.lastPathComponent
        }
        if let fileURL = primaryPane.selectedTab?.url {
            return fileURL.lastPathComponent
        }
        return "OpenPane"
    }

    var hasWorkspace: Bool {
        rootURL != nil
    }

    var canAcceptExternalOpenInCurrentWindow: Bool {
        rootURL == nil
            && primaryPane.tabs.isEmpty
            && (secondaryPane?.tabs.isEmpty ?? true)
            && !documents.hasDirtySessions
    }

    var selectedURL: URL? {
        pane(activePane).selectedTab?.url
    }

    @discardableResult
    func activateOpenFile(_ url: URL) -> Bool {
        let canonicalURL = url.standardizedFileURL
        for paneID in WorkspacePaneID.allCases {
            guard let tab = pane(paneID).tabs.first(where: {
                $0.url.standardizedFileURL == canonicalURL
            }) else {
                continue
            }
            select(tab.id, in: paneID)
            return true
        }
        return false
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        defer { discoverRecoverySnapshots() }

        switch launch.kind {
        case .restore:
            if !restorePersistedWorkspace() {
                primaryPane = WorkspacePaneState()
            }
        case .folder:
            if let location = launch.resolvedLocation() {
                openFolder(
                    location.url,
                    bookmarkData: location.bookmarkData
                )
            }
        case .file:
            if let location = launch.resolvedLocation() {
                openLooseFile(
                    location.url,
                    bookmarkData: location.bookmarkData
                )
            }
        }
    }

    func openFolder(_ url: URL, bookmarkData: Data? = nil) {
        let canonicalURL = url.standardizedFileURL
        if rootURL?.standardizedFileURL == canonicalURL {
            return
        }
        if rootURL != canonicalURL, documents.hasDirtySessions {
            operationError = "Save or discard your open edits before replacing this workspace."
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: canonicalURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            operationError = "“\(url.lastPathComponent)” is not an accessible folder."
            return
        }

        quickOpenTask?.cancel()
        documents.reset()
        securityScope = SecurityScopeAccess(url: canonicalURL)
        rootBookmarkData = bookmarkData
            ?? WorkspaceSecurityBookmark.create(for: canonicalURL)
        looseFileBookmarkData = nil
        additionalSecurityScopes.removeAll()
        additionalBookmarkData.removeAll()
        rootURL = canonicalURL
        childrenByDirectory.removeAll()
        expandedDirectories = [canonicalURL]
        quickOpenFiles = []
        primaryPane = WorkspacePaneState()
        secondaryPane = nil
        activePane = .primary
        loadDirectory(canonicalURL)
        rebuildQuickOpenIndex()
        persist()
    }

    func openLooseFile(_ url: URL, bookmarkData: Data? = nil) {
        let canonicalURL = url.standardizedFileURL
        if selectedURL?.standardizedFileURL == canonicalURL,
           rootURL == nil {
            return
        }
        if selectedURL != nil,
           selectedURL?.standardizedFileURL != canonicalURL,
           documents.hasDirtySessions {
            operationError = "Save or discard your open edits before replacing this file."
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: canonicalURL.path,
            isDirectory: &isDirectory
        ), !isDirectory.boolValue else {
            operationError = "“\(url.lastPathComponent)” is not an accessible file."
            return
        }

        documents.reset()
        securityScope = SecurityScopeAccess(url: canonicalURL)
        rootBookmarkData = nil
        looseFileBookmarkData = bookmarkData
            ?? WorkspaceSecurityBookmark.create(for: canonicalURL)
        additionalSecurityScopes.removeAll()
        additionalBookmarkData.removeAll()
        rootURL = nil
        childrenByDirectory.removeAll()
        expandedDirectories.removeAll()
        quickOpenFiles = []
        secondaryPane = nil
        activePane = .primary
        primaryPane = WorkspacePaneState()
        primaryPane.open(canonicalURL, behavior: .pinned)
        persist()
    }

    func handleExternalURLs(_ urls: [URL]) {
        guard let firstURL = urls.first else { return }
        hasStarted = true
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: firstURL.path,
            isDirectory: &isDirectory
        ) else {
            operationError = "“\(firstURL.lastPathComponent)” no longer exists."
            return
        }

        if isDirectory.boolValue {
            openFolder(firstURL)
            return
        }

        for url in urls {
            open(url, behavior: .pinned, in: activePane)
        }
    }

    func pane(_ paneID: WorkspacePaneID) -> WorkspacePaneState {
        switch paneID {
        case .primary:
            primaryPane
        case .secondary:
            secondaryPane ?? WorkspacePaneState()
        }
    }

    func bindingPane(_ paneID: WorkspacePaneID) -> BindingProxy<WorkspacePaneState> {
        BindingProxy(
            get: { [weak self] in
                guard let self else { return WorkspacePaneState() }
                return self.pane(paneID)
            },
            set: { [weak self] state in
                guard let self else { return }
                switch paneID {
                case .primary:
                    self.primaryPane = state
                case .secondary:
                    self.secondaryPane = state
                }
                self.persist()
            }
        )
    }

    func open(
        _ url: URL,
        behavior: WorkspaceOpenBehavior = .preview,
        in paneID: WorkspacePaneID? = nil
    ) {
        let destination = paneID ?? activePane
        let canonicalURL = url.standardizedFileURL
        retainAccessIfOutsideWorkspace(canonicalURL)
        var paneState = pane(destination)
        paneState.open(canonicalURL, behavior: behavior)
        setPane(paneState, for: destination)
        activePane = destination
        persist()
    }

    func pin(_ tabID: WorkspaceTab.ID? = nil, in paneID: WorkspacePaneID) {
        var paneState = pane(paneID)
        paneState.pin(tabID)
        setPane(paneState, for: paneID)
        persist()
    }

    func select(_ tabID: WorkspaceTab.ID, in paneID: WorkspacePaneID) {
        var paneState = pane(paneID)
        paneState.select(tabID)
        setPane(paneState, for: paneID)
        activePane = paneID
        persist()
    }

    func updateViewMode(
        _ rawValue: String,
        for tabID: WorkspaceTab.ID,
        in paneID: WorkspacePaneID
    ) {
        var paneState = pane(paneID)
        guard let index = paneState.tabs.firstIndex(
            where: { $0.id == tabID }
        ) else {
            return
        }
        guard paneState.tabs[index].viewModeRawValue != rawValue else {
            return
        }
        paneState.tabs[index].viewModeRawValue = rawValue
        setPane(paneState, for: paneID)
        persist()
    }

    func updateEditorState(
        _ editorState: TextEditorState,
        for tabID: WorkspaceTab.ID,
        in paneID: WorkspacePaneID
    ) {
        var paneState = pane(paneID)
        guard let index = paneState.tabs.firstIndex(
            where: { $0.id == tabID }
        ) else {
            return
        }
        guard paneState.tabs[index].editorState != editorState else {
            return
        }
        paneState.tabs[index].editorState = editorState
        setPane(paneState, for: paneID)
        schedulePersist()
    }

    func close(_ tabID: WorkspaceTab.ID, in paneID: WorkspacePaneID) {
        let paneState = pane(paneID)
        if let tab = paneState.tabs.first(where: { $0.id == tabID }),
           documents.session(for: tab.url)?.isDirty == true,
           !isOpenInOtherPane(tab.url, from: paneID) {
            pendingTabClose = PendingWorkspaceTabClose(
                tabID: tabID,
                paneID: paneID,
                url: tab.url
            )
            return
        }
        performClose(tabID, in: paneID)
    }

    func saveAndClosePendingTab() async {
        guard let pendingTabClose,
              let session = documents.session(for: pendingTabClose.url) else {
            self.pendingTabClose = nil
            return
        }
        do {
            try await documents.save(session)
            self.pendingTabClose = nil
            performClose(pendingTabClose.tabID, in: pendingTabClose.paneID)
        } catch {
            operationError = error.localizedDescription
        }
    }

    func discardAndClosePendingTab() async {
        guard let pendingTabClose,
              let session = documents.session(for: pendingTabClose.url) else {
            self.pendingTabClose = nil
            return
        }
        do {
            try await documents.reload(session)
            self.pendingTabClose = nil
            performClose(pendingTabClose.tabID, in: pendingTabClose.paneID)
        } catch {
            operationError = error.localizedDescription
        }
    }

    func cancelPendingTabClose() {
        pendingTabClose = nil
    }

    func openRecoverySnapshots() {
        let snapshots = pendingRecoverySnapshotURLs
        pendingRecoverySnapshotURLs = []
        for snapshot in snapshots {
            open(snapshot, behavior: .pinned, in: activePane)
        }
    }

    func revealRecoverySnapshots() {
        guard let first = pendingRecoverySnapshotURLs.first else { return }
        NSWorkspace.shared.activateFileViewerSelecting([first])
        pendingRecoverySnapshotURLs = []
    }

    func dismissRecoveryOffer() {
        pendingRecoverySnapshotURLs = []
    }

    private func performClose(
        _ tabID: WorkspaceTab.ID,
        in paneID: WorkspacePaneID
    ) {
        var paneState = pane(paneID)
        paneState.close(tabID)
        setPane(paneState, for: paneID)

        if paneID == .secondary, paneState.tabs.isEmpty {
            secondaryPane = nil
            activePane = .primary
        }
        discardUnusedDocumentSessions()
        persist()
    }

    func createSplit(axis: WorkspaceSplitAxis? = nil) {
        if let axis {
            splitAxis = axis
        }

        guard secondaryPane == nil else {
            activePane = .secondary
            persist()
            return
        }

        var newPane = WorkspacePaneState()
        if let selectedURL = primaryPane.selectedTab?.url {
            newPane.open(selectedURL, behavior: .pinned)
        }
        secondaryPane = newPane
        activePane = .secondary
        persist()
    }

    func closeSplit() {
        guard let secondaryPane else { return }

        var mergedPrimary = primaryPane
        for tab in secondaryPane.tabs where !mergedPrimary.tabs.contains(
            where: { $0.url.standardizedFileURL == tab.url.standardizedFileURL }
        ) {
            mergedPrimary.open(tab.url, behavior: tab.isPinned ? .pinned : .preview)
        }
        primaryPane = mergedPrimary
        self.secondaryPane = nil
        activePane = .primary
        persist()
    }

    func moveSelectedTabToOtherPane() {
        let sourceID = activePane
        let destinationID: WorkspacePaneID =
            sourceID == .primary ? .secondary : .primary

        if destinationID == .secondary, secondaryPane == nil {
            secondaryPane = WorkspacePaneState()
        }

        guard let selectedTab = pane(sourceID).selectedTab else { return }
        var destination = pane(destinationID)
        destination.open(
            selectedTab.url,
            behavior: selectedTab.isPinned ? .pinned : .preview
        )
        setPane(destination, for: destinationID)

        var source = pane(sourceID)
        source.close(selectedTab.id)
        setPane(source, for: sourceID)
        activePane = destinationID
        persist()
    }

    func setExpanded(_ url: URL, expanded: Bool) {
        let canonicalURL = url.standardizedFileURL
        if expanded {
            expandedDirectories.insert(canonicalURL)
            loadDirectory(canonicalURL)
        } else {
            expandedDirectories.remove(canonicalURL)
        }
        persist()
    }

    func isExpanded(_ url: URL) -> Bool {
        expandedDirectories.contains(url.standardizedFileURL)
    }

    func children(of directory: URL) -> [WorkspaceTreeEntry] {
        childrenByDirectory[directory.standardizedFileURL] ?? []
    }

    func loadDirectory(_ directory: URL, refresh: Bool = false) {
        let canonicalURL = directory.standardizedFileURL
        guard refresh || childrenByDirectory[canonicalURL] == nil else {
            return
        }
        guard !loadingDirectories.contains(canonicalURL) else { return }

        loadingDirectories.insert(canonicalURL)
        let showAllFiles = showAllFiles

        Task {
            let entries = await Self.enumerateDirectory(
                canonicalURL,
                showAllFiles: showAllFiles
            )
            guard !Task.isCancelled else { return }
            loadingDirectories.remove(canonicalURL)
            childrenByDirectory[canonicalURL] = entries
        }
    }

    func reloadParent(of url: URL) {
        let parent = url.deletingLastPathComponent().standardizedFileURL
        childrenByDirectory[parent] = nil
        loadDirectory(parent, refresh: true)
        rebuildQuickOpenIndex()
    }

    func createFile(named name: String, in directory: URL? = nil) {
        createItem(named: name, in: directory, isDirectory: false)
    }

    func createFolder(named name: String, in directory: URL? = nil) {
        createItem(named: name, in: directory, isDirectory: true)
    }

    func rename(_ url: URL, to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validateLeafName(trimmedName) else { return }

        let destination = url.deletingLastPathComponent()
            .appending(path: trimmedName)
        guard destination.standardizedFileURL != url.standardizedFileURL else {
            return
        }

        do {
            try FileManager.default.moveItem(at: url, to: destination)
            if let access = additionalSecurityScopes.removeValue(
                forKey: url.standardizedFileURL
            ) {
                additionalSecurityScopes[destination.standardizedFileURL] =
                    access
            }
            additionalBookmarkData[url.standardizedFileURL] = nil
            if let bookmark = WorkspaceSecurityBookmark.create(
                for: destination
            ) {
                additionalBookmarkData[destination.standardizedFileURL] =
                    bookmark
            }
            documents.updateURL(from: url, to: destination)
            updateTabURLs(from: url, to: destination)
            reloadParent(of: destination)
            persist()
        } catch {
            operationError = error.localizedDescription
        }
    }

    func duplicate(_ url: URL) {
        let manager = FileManager.default
        let parent = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let extensionName = url.pathExtension
        var copyNumber = 1
        var destination: URL

        repeat {
            let suffix = copyNumber == 1 ? " copy" : " copy \(copyNumber)"
            var name = base + suffix
            if !extensionName.isEmpty {
                name += ".\(extensionName)"
            }
            destination = parent.appending(path: name)
            copyNumber += 1
        } while manager.fileExists(atPath: destination.path)

        do {
            try manager.copyItem(at: url, to: destination)
            reloadParent(of: destination)
            open(destination, behavior: .pinned)
        } catch {
            operationError = error.localizedDescription
        }
    }

    func move(_ url: URL, to destinationDirectory: URL) {
        let access = SecurityScopeAccess(url: destinationDirectory)
        let destination = destinationDirectory.appending(
            path: url.lastPathComponent
        )

        do {
            try FileManager.default.moveItem(at: url, to: destination)
            additionalSecurityScopes[destination.standardizedFileURL] = access
            if let bookmark = WorkspaceSecurityBookmark.create(
                for: destination
            ) {
                additionalBookmarkData[destination.standardizedFileURL] =
                    bookmark
            }
            additionalSecurityScopes[url.standardizedFileURL] = nil
            additionalBookmarkData[url.standardizedFileURL] = nil
            documents.updateURL(from: url, to: destination)
            updateTabURLs(from: url, to: destination)
            reloadParent(of: url)
            if destinationDirectory != url.deletingLastPathComponent() {
                childrenByDirectory[destinationDirectory.standardizedFileURL] = nil
                loadDirectory(destinationDirectory, refresh: true)
            }
            persist()
        } catch {
            operationError = error.localizedDescription
        }
    }

    func moveToTrash(_ url: URL) {
        guard !documents.hasDirtySession(containedIn: url) else {
            operationError = "Save or discard open changes before moving this item to the Trash."
            return
        }
        do {
            var resultingURL: NSURL?
            try FileManager.default.trashItem(
                at: url,
                resultingItemURL: &resultingURL
            )
            documents.removeSessions(containedIn: url)
            removeTabs(containedIn: url)
            reloadParent(of: url)
            persist()
        } catch {
            operationError = error.localizedDescription
        }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyPath(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }

    func rebuildQuickOpenIndex() {
        quickOpenTask?.cancel()
        guard let rootURL else {
            quickOpenFiles = []
            isIndexingQuickOpen = false
            return
        }

        let showAllFiles = showAllFiles
        isIndexingQuickOpen = true
        quickOpenTask = Task {
            let files = await Self.indexFiles(
                below: rootURL,
                showAllFiles: showAllFiles
            )
            guard !Task.isCancelled else { return }
            quickOpenFiles = files
            isIndexingQuickOpen = false
        }
    }

    func relativePath(for url: URL) -> String {
        guard let rootURL else { return url.lastPathComponent }
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else { return filePath }
        return String(filePath.dropFirst(prefix.count))
    }

    private func setPane(
        _ paneState: WorkspacePaneState,
        for paneID: WorkspacePaneID
    ) {
        switch paneID {
        case .primary:
            primaryPane = paneState
        case .secondary:
            secondaryPane = paneState
        }
    }

    private func retainAccessIfOutsideWorkspace(_ url: URL) {
        if let rootURL {
            let rootPath = rootURL.standardizedFileURL.path
            let candidatePath = url.standardizedFileURL.path
            if candidatePath == rootPath
                || candidatePath.hasPrefix(
                    rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
                )
            {
                return
            }
        }
        let canonicalURL = url.standardizedFileURL
        if additionalSecurityScopes[canonicalURL] == nil {
            additionalSecurityScopes[canonicalURL] = SecurityScopeAccess(
                url: canonicalURL
            )
            if let bookmark = WorkspaceSecurityBookmark.create(
                for: canonicalURL
            ) {
                additionalBookmarkData[canonicalURL] = bookmark
            }
        }
    }

    private func createItem(
        named name: String,
        in directory: URL?,
        isDirectory: Bool
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validateLeafName(trimmedName) else { return }
        guard let parent = directory ?? rootURL else {
            operationError = "Open a folder before creating workspace items."
            return
        }

        let destination = parent.appending(path: trimmedName)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            operationError = "An item named “\(trimmedName)” already exists."
            return
        }

        do {
            if isDirectory {
                try FileManager.default.createDirectory(
                    at: destination,
                    withIntermediateDirectories: false
                )
                expandedDirectories.insert(parent.standardizedFileURL)
            } else {
                guard FileManager.default.createFile(
                    atPath: destination.path,
                    contents: Data()
                ) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                open(destination, behavior: .pinned)
            }
            reloadParent(of: destination)
        } catch {
            operationError = error.localizedDescription
        }
    }

    private func validateLeafName(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/") else {
            operationError = "Enter a single valid file or folder name."
            return false
        }
        return true
    }

    private func discoverRecoverySnapshots() {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return
        }
        let directory = base
            .appendingPathComponent("OpenPane", isDirectory: true)
            .appendingPathComponent("Recovery", isDirectory: true)
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentModificationDateKey
        ]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        pendingRecoverySnapshotURLs = files.filter { url in
            guard url.pathExtension.lowercased() == "txt" else {
                return false
            }
            return (try? url.resourceValues(forKeys: keys).isRegularFile)
                == true
        }.sorted { lhs, rhs in
            let left = try? lhs.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            let right = try? rhs.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            return (left ?? .distantPast) > (right ?? .distantPast)
        }
    }

    private func updateTabURLs(from source: URL, to destination: URL) {
        func updated(_ paneState: WorkspacePaneState) -> WorkspacePaneState {
            var result = paneState
            let sourcePath = source.standardizedFileURL.path
            let prefix = sourcePath.hasSuffix("/") ? sourcePath : sourcePath + "/"

            for index in result.tabs.indices {
                let currentPath = result.tabs[index].url.standardizedFileURL.path
                if currentPath == sourcePath {
                    result.tabs[index].url = destination.standardizedFileURL
                } else if currentPath.hasPrefix(prefix) {
                    let suffix = currentPath.dropFirst(prefix.count)
                    result.tabs[index].url = destination.appending(
                        path: String(suffix)
                    )
                }
            }
            return result
        }

        primaryPane = updated(primaryPane)
        if let secondaryPane {
            self.secondaryPane = updated(secondaryPane)
        }
    }

    private func removeTabs(containedIn url: URL) {
        let targetPath = url.standardizedFileURL.path
        let prefix = targetPath.hasSuffix("/") ? targetPath : targetPath + "/"

        func removing(from paneState: WorkspacePaneState) -> WorkspacePaneState {
            var result = paneState
            let identifiers = result.tabs
                .filter {
                    let path = $0.url.standardizedFileURL.path
                    return path == targetPath || path.hasPrefix(prefix)
                }
                .map(\.id)
            for identifier in identifiers {
                result.close(identifier)
            }
            return result
        }

        primaryPane = removing(from: primaryPane)
        if let secondaryPane {
            let result = removing(from: secondaryPane)
            self.secondaryPane = result.tabs.isEmpty ? nil : result
        }
        discardUnusedDocumentSessions()
    }

    private func discardUnusedDocumentSessions() {
        let URLs = primaryPane.tabs.map(\.url)
            + (secondaryPane?.tabs.map(\.url) ?? [])
        documents.discardUnusedSessions(openURLs: Set(URLs))
    }

    private func isOpenInOtherPane(
        _ url: URL,
        from paneID: WorkspacePaneID
    ) -> Bool {
        let otherPaneID: WorkspacePaneID =
            paneID == .primary ? .secondary : .primary
        return pane(otherPaneID).tabs.contains {
            $0.url.standardizedFileURL == url.standardizedFileURL
        }
    }

    private func persist() {
        guard rootURL != nil
            || !primaryPane.tabs.isEmpty
            || !(secondaryPane?.tabs.isEmpty ?? true) else {
            return
        }
        let rootPath = rootURL?.standardizedFileURL.path
        if let rootURL, rootBookmarkData == nil {
            rootBookmarkData = WorkspaceSecurityBookmark.create(for: rootURL)
        }

        let looseFileURL = rootURL == nil
            ? primaryPane.tabs.first?.url.standardizedFileURL
            : nil
        if let looseFileURL, looseFileBookmarkData == nil {
            looseFileBookmarkData = WorkspaceSecurityBookmark.create(
                for: looseFileURL
            )
        }

        let expandedPaths: Set<String>
        if let rootPath {
            expandedPaths = Set(
                expandedDirectories.compactMap { directory in
                    let path = directory.standardizedFileURL.path
                    if path == rootPath {
                        return ""
                    }
                    let prefix = rootPath.hasSuffix("/")
                        ? rootPath
                        : rootPath + "/"
                    guard path.hasPrefix(prefix) else { return nil }
                    return String(path.dropFirst(prefix.count))
                }
            )
        } else {
            expandedPaths = []
        }

        let tabURLs = Set(
            primaryPane.tabs.map(\.url.standardizedFileURL)
                + (secondaryPane?.tabs.map(\.url.standardizedFileURL) ?? [])
        )
        let outsideBookmarks = tabURLs.compactMap {
            url -> WorkspacePersistedBookmark? in
            if let rootURL, Self.contains(url, in: rootURL) {
                return nil
            }
            let bookmark = additionalBookmarkData[url]
                ?? (url == looseFileURL ? looseFileBookmarkData : nil)
                ?? WorkspaceSecurityBookmark.create(for: url)
            return WorkspacePersistedBookmark(
                bookmarkData: bookmark,
                pathFallback: url.path
            )
        }

        let state = WorkspacePersistedState(
            rootBookmark: rootBookmarkData,
            rootPathFallback: rootPath,
            looseFileBookmark: looseFileBookmarkData,
            looseFilePathFallback: looseFileURL?.path,
            additionalBookmarks: outsideBookmarks,
            primaryPane: primaryPane,
            secondaryPane: secondaryPane,
            splitAxis: splitAxis,
            showAllFiles: showAllFiles,
            expandedRelativePaths: expandedPaths
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: Self.persistedStateKey)
    }

    private func schedulePersist() {
        statePersistTask?.cancel()
        statePersistTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            self?.persist()
        }
    }

    private func restorePersistedWorkspace() -> Bool {
        guard let data = UserDefaults.standard.data(
            forKey: Self.persistedStateKey
        ), let state = try? JSONDecoder().decode(
            WorkspacePersistedState.self,
            from: data
        ) else {
            return false
        }

        let rootLocation = WorkspaceSecurityBookmark.resolve(
            state.rootBookmark,
            fallbackPath: state.rootPathFallback
        )
        let looseLocation = WorkspaceSecurityBookmark.resolve(
            state.looseFileBookmark,
            fallbackPath: state.looseFilePathFallback
        )
        guard rootLocation != nil || looseLocation != nil else {
            return false
        }

        let principalLocation = rootLocation ?? looseLocation
        guard let principalLocation,
              FileManager.default.fileExists(
                atPath: principalLocation.url.path
              ) else {
            return false
        }

        securityScope = SecurityScopeAccess(url: principalLocation.url)
        rootBookmarkData = rootLocation?.bookmarkData
        looseFileBookmarkData = looseLocation?.bookmarkData

        var remappedURLs: [String: URL] = [:]
        if let originalRootPath = state.rootPathFallback,
           let rootLocation {
            remappedURLs[originalRootPath] = rootLocation.url
        }
        if let originalLoosePath = state.looseFilePathFallback,
           let looseLocation {
            remappedURLs[originalLoosePath] = looseLocation.url
        }
        for persisted in state.additionalBookmarks ?? [] {
            guard let location = WorkspaceSecurityBookmark.resolve(
                persisted.bookmarkData,
                fallbackPath: persisted.pathFallback
            ), FileManager.default.fileExists(atPath: location.url.path) else {
                continue
            }
            let canonicalURL = location.url.standardizedFileURL
            remappedURLs[persisted.pathFallback] = canonicalURL
            additionalSecurityScopes[canonicalURL] = SecurityScopeAccess(
                url: canonicalURL
            )
            if let bookmark = location.bookmarkData {
                additionalBookmarkData[canonicalURL] = bookmark
            }
        }

        isRestoringPersistedState = true
        defer { isRestoringPersistedState = false }
        rootURL = rootLocation?.url.standardizedFileURL
        primaryPane = filteringMissingTabs(
            remappingTabs(state.primaryPane, using: remappedURLs)
        )
        secondaryPane = state.secondaryPane.map {
            filteringMissingTabs(remappingTabs($0, using: remappedURLs))
        }
        if secondaryPane?.tabs.isEmpty == true {
            secondaryPane = nil
        }
        splitAxis = state.splitAxis
        showAllFiles = state.showAllFiles
        if let restoredRoot = rootLocation?.url.standardizedFileURL {
            expandedDirectories = Set(
                state.expandedRelativePaths.map { path in
                    path.isEmpty
                        ? restoredRoot
                        : restoredRoot.appending(path: path).standardizedFileURL
                }
            )
            expandedDirectories.insert(restoredRoot)
            loadDirectory(restoredRoot)
            for directory in expandedDirectories
                where directory != restoredRoot {
                loadDirectory(directory)
            }
            rebuildQuickOpenIndex()
        } else {
            expandedDirectories = []
            quickOpenFiles = []
        }
        Task { @MainActor [weak self] in
            self?.persist()
        }
        return true
    }

    private func remappingTabs(
        _ paneState: WorkspacePaneState,
        using remappedURLs: [String: URL]
    ) -> WorkspacePaneState {
        var result = paneState
        for index in result.tabs.indices {
            let originalPath = result.tabs[index].url.standardizedFileURL.path
            if let remapped = remappedURLs[originalPath] {
                result.tabs[index].url = remapped
            }
        }
        return result
    }

    private func filteringMissingTabs(
        _ paneState: WorkspacePaneState
    ) -> WorkspacePaneState {
        var result = paneState
        let missingIDs = result.tabs
            .filter { !FileManager.default.fileExists(atPath: $0.url.path) }
            .map(\.id)
        for identifier in missingIDs {
            result.close(identifier)
        }
        return result
    }

    nonisolated private static func contains(
        _ candidateURL: URL,
        in rootURL: URL
    ) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let candidatePath = candidateURL.standardizedFileURL.path
        guard candidatePath != rootPath else { return true }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return candidatePath.hasPrefix(prefix)
    }

    nonisolated private static func enumerateDirectory(
        _ directory: URL,
        showAllFiles: Bool
    ) async -> [WorkspaceTreeEntry] {
        await Task.detached(priority: .userInitiated) {
            let keys: Set<URLResourceKey> = [
                .isDirectoryKey,
                .isSymbolicLinkKey
            ]
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: []
            ) else {
                return []
            }

            return urls.compactMap { url -> WorkspaceTreeEntry? in
                guard WorkspaceTreePolicy.shouldShow(
                    name: url.lastPathComponent,
                    showAllFiles: showAllFiles
                ) else {
                    return nil
                }
                let values = try? url.resourceValues(forKeys: keys)
                let isDirectory = values?.isDirectory == true
                let kind: WorkspaceTreeEntry.Kind
                if values?.isSymbolicLink == true {
                    kind = .symbolicLink(isDirectory: isDirectory)
                } else {
                    kind = isDirectory ? .directory : .file
                }
                return WorkspaceTreeEntry(
                    url: url.standardizedFileURL,
                    kind: kind
                )
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }
                return lhs.name.localizedStandardCompare(rhs.name)
                    == .orderedAscending
            }
        }.value
    }

    nonisolated private static func indexFiles(
        below rootURL: URL,
        showAllFiles: Bool
    ) async -> [URL] {
        await Task.detached(priority: .utility) {
            indexFilesSynchronously(
                below: rootURL,
                showAllFiles: showAllFiles
            )
        }.value
    }

    nonisolated private static func indexFilesSynchronously(
        below rootURL: URL,
        showAllFiles: Bool
    ) -> [URL] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            if Task.isCancelled { return [] }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory == true
            let isSymbolicLink = values?.isSymbolicLink == true

            if !WorkspaceTreePolicy.shouldShow(
                name: url.lastPathComponent,
                showAllFiles: showAllFiles
            ) {
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }
            if isSymbolicLink && isDirectory {
                enumerator.skipDescendants()
                continue
            }
            if values?.isRegularFile == true || (isSymbolicLink && !isDirectory) {
                files.append(url.standardizedFileURL)
            }
        }
        return files.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }
}

/// A tiny closure-backed binding used to keep the state model independent of SwiftUI.
struct BindingProxy<Value> {
    let get: () -> Value
    let set: (Value) -> Void
}

private final class SecurityScopeAccess {
    private let url: URL
    private let didStart: Bool

    init(url: URL) {
        self.url = url
        didStart = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if didStart {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
