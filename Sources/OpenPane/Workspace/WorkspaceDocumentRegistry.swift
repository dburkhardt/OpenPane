import Combine
import Foundation
import OpenPaneCore

/// Owns the runtime file sessions for a workspace window.
///
/// Tabs in both editor groups resolve through this registry, so opening one
/// file in two groups shares text, dirty state, revision, and save metadata.
@MainActor
final class WorkspaceDocumentRegistry: ObservableObject {
    let fileIO: FileIOActor

    @Published private(set) var sessionsByURL: [URL: FileSession] = [:]

    private var loadingTasks: [URL: Task<LoadedFile, Error>] = [:]

    init(fileIO: FileIOActor = FileIOActor()) {
        self.fileIO = fileIO
    }

    var hasDirtySessions: Bool {
        sessionsByURL.values.contains(where: \.isDirty)
    }

    var dirtySessions: [FileSession] {
        sessionsByURL.values
            .filter(\.isDirty)
            .sorted {
                $0.url.path.localizedStandardCompare($1.url.path)
                    == .orderedAscending
            }
    }

    func hasDirtySession(containedIn url: URL) -> Bool {
        let targetPath = url.standardizedFileURL.path
        let prefix = targetPath.hasSuffix("/") ? targetPath : targetPath + "/"
        return sessionsByURL.contains { element in
            let path = element.key.path
            return (path == targetPath || path.hasPrefix(prefix))
                && element.value.isDirty
        }
    }

    func reset() {
        for task in loadingTasks.values {
            task.cancel()
        }
        loadingTasks.removeAll()
        sessionsByURL.removeAll()
    }

    /// Persists every unsaved text buffer outside the source tree before a
    /// window-close or application-termination decision is presented.
    ///
    /// A failure is intentionally surfaced to the lifecycle coordinator so it
    /// can keep the window open instead of losing the only current copy.
    func flushRecoverySnapshots() async throws {
        for session in dirtySessions {
            guard let text = session.text else {
                throw WorkspaceDocumentRegistryError.missingRecoveryText(
                    session.url
                )
            }
            _ = try await fileIO.writeRecoverySnapshot(
                sessionID: session.id,
                sourceURL: session.url,
                text: text
            )
        }
    }

    func saveAllDirtySessions() async throws {
        for session in dirtySessions {
            try await save(session)
        }
    }

    /// Abandons runtime buffers only after their recovery files are removed.
    /// This is used exclusively after the user explicitly chooses Discard
    /// while closing a window or quitting the app.
    func discardAllDirtySessionsForClosing() async throws {
        for session in dirtySessions {
            try await fileIO.removeRecoverySnapshot(sessionID: session.id)
        }
        reset()
    }

    func session(for url: URL) -> FileSession? {
        sessionsByURL[url.standardizedFileURL]
    }

    func load(
        _ url: URL,
        isPinned: Bool
    ) async throws -> FileSession {
        let canonicalURL = url.standardizedFileURL
        if let existing = sessionsByURL[canonicalURL] {
            if isPinned {
                existing.isPinned = true
            }
            if !existing.isDirty, !existing.isEditing {
                let loadedFile = try await fileIO.load(url: canonicalURL)
                existing.reload(from: loadedFile)
            }
            return existing
        }

        let task: Task<LoadedFile, Error>
        if let current = loadingTasks[canonicalURL] {
            task = current
        } else {
            task = Task {
                try await fileIO.load(url: canonicalURL)
            }
            loadingTasks[canonicalURL] = task
        }

        do {
            let loadedFile = try await task.value
            loadingTasks[canonicalURL] = nil

            // Another pane may have completed the same load first.
            if let existing = sessionsByURL[canonicalURL] {
                if isPinned {
                    existing.isPinned = true
                }
                return existing
            }

            let session = FileSession(
                loadedFile: loadedFile,
                isPinned: isPinned
            )
            sessionsByURL[canonicalURL] = session
            return session
        } catch {
            loadingTasks[canonicalURL] = nil
            throw error
        }
    }

    func reload(_ session: FileSession) async throws {
        let loadedFile = try await fileIO.load(url: session.url)
        session.reload(from: loadedFile)
    }

    @discardableResult
    func save(
        _ session: FileSession,
        overwriteExternalChanges: Bool = false
    ) async throws -> SaveReceipt {
        guard let text = session.text else {
            throw WorkspaceDocumentRegistryError.missingSaveMetadata
        }
        let decoded = try session.decodedTextForSaving()
        let bytes = try session.encodedCurrentText()
        let receipt = try await fileIO.save(
            text: text,
            decodedText: decoded,
            to: session.url,
            expectedFingerprint: session.fingerprint,
            overwriteExternalChanges: overwriteExternalChanges
        )
        session.markSaved(bytes: bytes, receipt: receipt)
        try? await fileIO.removeRecoverySnapshot(sessionID: session.id)
        return receipt
    }

    func updateURL(from source: URL, to destination: URL) {
        let sourceURL = source.standardizedFileURL
        let destinationURL = destination.standardizedFileURL
        let sourcePath = sourceURL.path
        let prefix = sourcePath.hasSuffix("/") ? sourcePath : sourcePath + "/"
        let affected = sessionsByURL.filter { element in
            element.key.path == sourcePath || element.key.path.hasPrefix(prefix)
        }

        for (oldURL, session) in affected {
            sessionsByURL[oldURL] = nil
            let newURL: URL
            if oldURL.path == sourcePath {
                newURL = destinationURL
            } else {
                newURL = destinationURL.appending(
                    path: String(oldURL.path.dropFirst(prefix.count))
                )
            }
            session.updateURL(newURL)
            sessionsByURL[newURL.standardizedFileURL] = session
        }
    }

    func removeSessions(containedIn url: URL) {
        let targetPath = url.standardizedFileURL.path
        let prefix = targetPath.hasSuffix("/") ? targetPath : targetPath + "/"
        sessionsByURL = sessionsByURL.filter { element in
            element.key.path != targetPath
                && !element.key.path.hasPrefix(prefix)
        }
    }

    func discardUnusedSessions(openURLs: Set<URL>) {
        let canonicalOpenURLs = Set(openURLs.map(\.standardizedFileURL))
        sessionsByURL = sessionsByURL.filter { element in
            canonicalOpenURLs.contains(element.key.standardizedFileURL)
                || element.value.isDirty
        }
    }
}

enum WorkspaceDocumentRegistryError: LocalizedError {
    case missingSaveMetadata
    case missingRecoveryText(URL)

    var errorDescription: String? {
        switch self {
        case .missingSaveMetadata:
            "OpenPane does not have enough source metadata to save this file safely."
        case .missingRecoveryText(let url):
            "OpenPane could not preserve the unsaved contents of “\(url.lastPathComponent)”."
        }
    }
}
