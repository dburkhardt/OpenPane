import Foundation
import Observation

public struct TextEditorState: Codable, Equatable, Sendable {
    public var cursorLocation: Int
    public var selectionLength: Int
    public var verticalScrollOffset: Double
    public var horizontalScrollOffset: Double

    public init(
        cursorLocation: Int = 0,
        selectionLength: Int = 0,
        verticalScrollOffset: Double = 0,
        horizontalScrollOffset: Double = 0
    ) {
        self.cursorLocation = cursorLocation
        self.selectionLength = selectionLength
        self.verticalScrollOffset = verticalScrollOffset
        self.horizontalScrollOffset = horizontalScrollOffset
    }
}

@MainActor
@Observable
public final class FileSession: Identifiable {
    public let id: UUID
    public private(set) var url: URL
    public private(set) var fileIdentity: FileIdentity
    public private(set) var classification: FileClassification
    public private(set) var fingerprint: FileFingerprint
    public var viewMode: FileViewMode
    public var isPinned: Bool
    public var isEditing: Bool
    public var editorState: TextEditorState
    public private(set) var revision: UInt64
    public private(set) var isDirty: Bool
    public private(set) var metadata: TextFileMetadata?
    public private(set) var originalBytes: Data
    public private(set) var originalText: String?
    private var tracksTextChanges: Bool
    public var text: String? {
        didSet {
            guard tracksTextChanges, text != oldValue else { return }
            revision &+= 1
            isDirty = text != originalText
        }
    }

    public init(
        loadedFile: LoadedFile,
        id: UUID = UUID(),
        viewMode: FileViewMode? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        url = loadedFile.url
        fileIdentity = loadedFile.fileIdentity
        classification = loadedFile.classification
        fingerprint = loadedFile.fingerprint
        self.viewMode = viewMode ?? loadedFile.classification.defaultViewMode
        self.isPinned = isPinned
        isEditing = false
        editorState = TextEditorState()
        revision = 0
        isDirty = false
        metadata = loadedFile.decodedText?.metadata
        originalBytes = loadedFile.data
        originalText = loadedFile.decodedText?.text
        tracksTextChanges = false
        text = loadedFile.decodedText?.text
        tracksTextChanges = true
    }

    public func beginEditing() {
        guard classification.isEditable else { return }
        isPinned = true
        isEditing = true
        if viewMode == .reader {
            viewMode = .source
        }
    }

    public func endEditing() {
        isEditing = false
    }

    public func updateURL(_ newURL: URL) {
        url = newURL.standardizedFileURL
        fileIdentity = FileIdentity(url: newURL)
    }

    public func encodedCurrentText() throws -> Data {
        guard let text, let metadata, let originalText else {
            throw TextCodecError.invalidText
        }
        return try TextCodec.encode(
            text,
            metadata: metadata,
            originalText: originalText,
            originalData: originalBytes
        )
    }

    public func decodedTextForSaving() throws -> DecodedText {
        guard let originalText, let metadata else {
            throw TextCodecError.invalidText
        }
        return DecodedText(
            text: originalText,
            originalText: originalText,
            originalData: originalBytes,
            metadata: metadata
        )
    }

    public func markSaved(bytes: Data, receipt: SaveReceipt) {
        originalBytes = bytes
        originalText = text
        fingerprint = receipt.fingerprint
        if var metadata {
            if let decoded = TextCodec.decode(bytes) {
                metadata.lineEndings = decoded.metadata.lineEndings
                metadata.originalLineEndings = decoded.metadata.originalLineEndings
            }
            metadata.originalByteCount = UInt64(bytes.count)
            metadata.hasTrailingNewline = text?.unicodeScalars.last.map {
                $0.value == 0x0A || $0.value == 0x0D
            } ?? false
            metadata.sourceFingerprint = receipt.fingerprint
            self.metadata = metadata
        }
        isDirty = false
    }

    public func reload(from loadedFile: LoadedFile) {
        url = loadedFile.url
        fileIdentity = loadedFile.fileIdentity
        classification = loadedFile.classification
        fingerprint = loadedFile.fingerprint
        originalBytes = loadedFile.data
        originalText = loadedFile.decodedText?.text
        metadata = loadedFile.decodedText?.metadata
        tracksTextChanges = false
        text = loadedFile.decodedText?.text
        tracksTextChanges = true
        isDirty = false
        isEditing = false
        if !classification.availableViewModes.contains(viewMode) {
            viewMode = classification.defaultViewMode
        }
        revision &+= 1
    }
}

public enum WorkspacePane: String, Codable, CaseIterable, Hashable, Sendable {
    case primary
    case secondary
}

public enum SplitOrientation: String, Codable, CaseIterable, Hashable, Sendable {
    case horizontal
    case vertical
}

public struct RestoredTabState: Codable, Equatable, Sendable {
    public var url: URL
    public var pane: WorkspacePane
    public var viewMode: FileViewMode
    public var isPinned: Bool
    public var editorState: TextEditorState

    public init(
        url: URL,
        pane: WorkspacePane,
        viewMode: FileViewMode,
        isPinned: Bool,
        editorState: TextEditorState
    ) {
        self.url = url
        self.pane = pane
        self.viewMode = viewMode
        self.isPinned = isPinned
        self.editorState = editorState
    }
}

public struct WorkspaceRestorationState: Codable, Equatable, Sendable {
    public var rootBookmarkData: Data?
    public var tabs: [RestoredTabState]
    public var selectedPrimaryURL: URL?
    public var selectedSecondaryURL: URL?
    public var splitOrientation: SplitOrientation?
    public var showAllFiles: Bool

    public init(
        rootBookmarkData: Data?,
        tabs: [RestoredTabState],
        selectedPrimaryURL: URL?,
        selectedSecondaryURL: URL?,
        splitOrientation: SplitOrientation?,
        showAllFiles: Bool
    ) {
        self.rootBookmarkData = rootBookmarkData
        self.tabs = tabs
        self.selectedPrimaryURL = selectedPrimaryURL
        self.selectedSecondaryURL = selectedSecondaryURL
        self.splitOrientation = splitOrientation
        self.showAllFiles = showAllFiles
    }
}

@MainActor
@Observable
public final class WorkspaceSession: Identifiable {
    public let id: UUID
    public var rootURL: URL?
    public var rootBookmarkData: Data?
    public var showAllFiles: Bool
    public var splitOrientation: SplitOrientation?
    public private(set) var sessions: [UUID: FileSession]
    public private(set) var primaryTabs: [UUID]
    public private(set) var secondaryTabs: [UUID]
    public var selectedPrimaryTab: UUID?
    public var selectedSecondaryTab: UUID?

    public init(
        id: UUID = UUID(),
        rootURL: URL? = nil,
        rootBookmarkData: Data? = nil,
        showAllFiles: Bool = false,
        splitOrientation: SplitOrientation? = nil
    ) {
        self.id = id
        self.rootURL = rootURL
        self.rootBookmarkData = rootBookmarkData
        self.showAllFiles = showAllFiles
        self.splitOrientation = splitOrientation
        sessions = [:]
        primaryTabs = []
        secondaryTabs = []
    }

    @discardableResult
    public func add(
        _ session: FileSession,
        to pane: WorkspacePane = .primary,
        select: Bool = true
    ) -> FileSession {
        if let existing = self.session(for: session.url) {
            if select { selectTab(existing.id, in: paneContaining(existing.id) ?? pane) }
            return existing
        }

        sessions[session.id] = session
        switch pane {
        case .primary:
            replacePreviewTabIfNeeded(with: session.id, in: .primary)
            if !primaryTabs.contains(session.id) { primaryTabs.append(session.id) }
            if select { selectedPrimaryTab = session.id }
        case .secondary:
            replacePreviewTabIfNeeded(with: session.id, in: .secondary)
            if !secondaryTabs.contains(session.id) { secondaryTabs.append(session.id) }
            if select { selectedSecondaryTab = session.id }
        }
        return session
    }

    public func session(for url: URL) -> FileSession? {
        let identity = FileIdentity(url: url)
        return sessions.values.first {
            $0.fileIdentity == identity || $0.url.standardizedFileURL == url.standardizedFileURL
        }
    }

    public func selectTab(_ id: UUID, in pane: WorkspacePane) {
        guard tabs(in: pane).contains(id) else { return }
        switch pane {
        case .primary: selectedPrimaryTab = id
        case .secondary: selectedSecondaryTab = id
        }
    }

    /// Displays an already-open session in another group without duplicating
    /// its buffers or dirty state.
    public func showSession(_ id: UUID, in pane: WorkspacePane, select: Bool = true) {
        guard sessions[id] != nil else { return }
        switch pane {
        case .primary:
            if !primaryTabs.contains(id) { primaryTabs.append(id) }
            if select { selectedPrimaryTab = id }
        case .secondary:
            if !secondaryTabs.contains(id) { secondaryTabs.append(id) }
            if select { selectedSecondaryTab = id }
        }
    }

    public func closeTab(_ id: UUID, in pane: WorkspacePane) {
        switch pane {
        case .primary:
            primaryTabs.removeAll { $0 == id }
            if selectedPrimaryTab == id { selectedPrimaryTab = primaryTabs.last }
        case .secondary:
            secondaryTabs.removeAll { $0 == id }
            if selectedSecondaryTab == id { selectedSecondaryTab = secondaryTabs.last }
        }
        if !primaryTabs.contains(id), !secondaryTabs.contains(id) {
            sessions[id] = nil
        }
    }

    public func tabs(in pane: WorkspacePane) -> [UUID] {
        switch pane {
        case .primary: primaryTabs
        case .secondary: secondaryTabs
        }
    }

    public func paneContaining(_ id: UUID) -> WorkspacePane? {
        if primaryTabs.contains(id) { return .primary }
        if secondaryTabs.contains(id) { return .secondary }
        return nil
    }

    public func restorationState() -> WorkspaceRestorationState {
        var tabs: [RestoredTabState] = []
        for (pane, identifiers) in [
            (WorkspacePane.primary, primaryTabs),
            (WorkspacePane.secondary, secondaryTabs),
        ] {
            for id in identifiers {
                guard let session = sessions[id] else { continue }
                tabs.append(
                    RestoredTabState(
                        url: session.url,
                        pane: pane,
                        viewMode: session.viewMode,
                        isPinned: session.isPinned,
                        editorState: session.editorState
                    )
                )
            }
        }
        return WorkspaceRestorationState(
            rootBookmarkData: rootBookmarkData,
            tabs: tabs,
            selectedPrimaryURL: selectedPrimaryTab.flatMap { sessions[$0]?.url },
            selectedSecondaryURL: selectedSecondaryTab.flatMap { sessions[$0]?.url },
            splitOrientation: splitOrientation,
            showAllFiles: showAllFiles
        )
    }

    private func replacePreviewTabIfNeeded(with newID: UUID, in pane: WorkspacePane) {
        let identifiers = tabs(in: pane)
        guard let previewID = identifiers.first(where: { sessions[$0]?.isPinned == false }),
              sessions[previewID]?.isDirty != true
        else {
            return
        }
        closeTab(previewID, in: pane)
    }
}
