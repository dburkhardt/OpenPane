import AppKit
import OpenPaneCore
import SwiftUI

/// Routes a selected workspace URL into the type-aware viewer/editor layer.
///
/// File contents live in `FileSession`, never in workspace restoration state.
struct WorkspaceDocumentView: View {
    let registry: WorkspaceDocumentRegistry
    let fileURL: URL
    let isPinned: Bool
    let isActive: Bool
    let initialViewModeRawValue: String?
    let initialEditorState: TextEditorState
    let onPin: () -> Void
    let onViewModeChange: (String) -> Void
    let onEditorStateChange: (TextEditorState) -> Void
    let onOpenURL: (URL) -> Void
    let onPreviewToSide: () -> Void

    @State private var session: FileSession?
    @State private var loadError: String?
    @State private var viewMode = FileViewMode.source

    var body: some View {
        Group {
            if let session {
                WorkspaceLoadedDocumentView(
                    session: session,
                    registry: registry,
                    isActive: isActive,
                    viewMode: $viewMode,
                    initialEditorState: initialEditorState,
                    onPin: onPin,
                    onViewModeChange: onViewModeChange,
                    onEditorStateChange: onEditorStateChange,
                    onOpenURL: onOpenURL,
                    onPreviewToSide: onPreviewToSide,
                    reload: load
                )
            } else if let loadError {
                ContentUnavailableView {
                    Label("File Couldn’t Be Opened", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again") {
                        Task { await load() }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Opening \(fileURL.lastPathComponent)…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: fileURL) {
            await load()
        }
        .onChange(of: isPinned) { _, newValue in
            session?.isPinned = newValue
        }
        .onChange(of: initialViewModeRawValue) { _, _ in
            if let session {
                restoreViewMode(on: session)
            }
        }
    }

    @MainActor
    private func load() async {
        loadError = nil
        do {
            if let existing = session,
               existing.url.standardizedFileURL == fileURL.standardizedFileURL {
                try await registry.reload(existing)
                existing.isPinned = isPinned
                restoreViewMode(on: existing)
            } else {
                session = try await registry.load(
                    fileURL,
                    isPinned: isPinned
                )
                if let session {
                    restoreViewMode(on: session)
                }
            }
        } catch {
            session = nil
            loadError = error.localizedDescription
        }
    }

    private func restoreViewMode(on session: FileSession) {
        if let initialViewModeRawValue,
           let mode = FileViewMode(rawValue: initialViewModeRawValue),
           session.classification.availableViewModes.contains(mode) {
            viewMode = mode
        } else {
            viewMode = session.classification.defaultViewMode
        }
    }
}

@MainActor
private struct WorkspaceLoadedDocumentView: View {
    @Bindable var session: FileSession
    let registry: WorkspaceDocumentRegistry
    let isActive: Bool
    @Binding var viewMode: FileViewMode
    let initialEditorState: TextEditorState
    let onPin: () -> Void
    let onViewModeChange: (String) -> Void
    let onEditorStateChange: (TextEditorState) -> Void
    let onOpenURL: (URL) -> Void
    let onPreviewToSide: () -> Void
    let reload: @MainActor () async -> Void

    @State private var wordWrap = true
    @State private var fontSize: CGFloat = 13
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showingSaveConflict = false
    @State private var showingDonePrompt = false
    @State private var lastFileStamp: WorkspaceFileStamp?

    var body: some View {
        routedContent
            .overlay {
                if isSaving {
                    ProgressView("Saving…")
                        .padding(14)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .shadow(radius: 8)
                }
            }
            .alert(
                "Save Failed",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    saveError = nil
                }
            } message: {
                Text(saveError ?? "")
            }
            .alert(
                "This File Changed Outside OpenPane",
                isPresented: $showingSaveConflict
            ) {
                Button("Reload") {
                    Task { await reloadAfterConflict() }
                }
                Button("Save Copy…") {
                    Task { await saveCopy() }
                }
                Button("Overwrite", role: .destructive) {
                    Task { _ = await save(overwriteExternalChanges: true) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Reload the file, save your edits to a new file, or explicitly overwrite the external changes."
                )
            }
            .alert(
                "Save Changes Before Leaving Edit Mode?",
                isPresented: $showingDonePrompt
            ) {
                Button("Save") {
                    Task {
                        if await save() {
                            session.endEditing()
                        }
                    }
                }
                Button("Discard Changes", role: .destructive) {
                    Task {
                        await reload()
                        session.endEditing()
                        lastFileStamp = WorkspaceFileStamp(url: session.url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("OpenPane never saves over the source file automatically.")
            }
            .onAppear {
                lastFileStamp = WorkspaceFileStamp(url: session.url)
                onViewModeChange(viewMode.rawValue)
            }
            .onChange(of: viewMode) { _, mode in
                onViewModeChange(mode.rawValue)
            }
            .task(id: session.id) {
                await monitorExternalChanges()
            }
            .task(id: session.revision) {
                await updateRecoverySnapshot()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .openPaneSave)
            ) { _ in
                guard isActive, session.isDirty else { return }
                Task { _ = await save() }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .openPaneToggleEditing
                )
            ) { _ in
                guard isActive else { return }
                requestEditing(!session.isEditing)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .openPaneFind)
            ) { _ in
                guard isActive else { return }
                showNativeFindInterface()
            }
    }

    @ViewBuilder
    private var routedContent: some View {
        switch session.classification.kind {
        case .markdown:
            markdownContent

        case .text(let languageID):
            textEditor(languageID: languageID)

        case .pdf:
            PDFReaderView(url: session.url, isActive: isActive)

        case .systemPreview:
            SystemPreviewView(url: session.url)

        case .binary:
            BinaryInspectorView(
                data: session.originalBytes,
                sourceURL: session.url,
                totalByteCount: boundedInt(
                    session.classification.totalByteCount
                )
            )
        }
    }

    private var markdownContent: some View {
        VStack(spacing: 0) {
            if !session.classification.isLargeFile {
                HStack {
                    Picker("Markdown View", selection: $viewMode) {
                        Text("Reader").tag(FileViewMode.reader)
                        Text("Source").tag(FileViewMode.source)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)

                    Button {
                        viewMode = .source
                        onPreviewToSide()
                    } label: {
                        Label(
                            "Preview to Side",
                            systemImage: "rectangle.split.2x1"
                        )
                    }
                    .help("Open Reader in the other editor group")

                    Spacer()

                    if viewMode == .reader,
                       session.classification.isEditable {
                        Button("Edit") {
                            requestEditing(true)
                        }
                        .keyboardShortcut("e", modifiers: .command)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(.bar)

                Divider()
            }

            if viewMode == .reader,
               !session.classification.isLargeFile {
                MarkdownReaderView(
                    source: session.text ?? "",
                    baseURL: session.url.deletingLastPathComponent(),
                    onOpenURL: onOpenURL
                )
            } else {
                textEditor(languageID: "markdown")
            }
        }
    }

    private func textEditor(languageID: String) -> some View {
        VStack(spacing: 0) {
            if session.classification.isLargeFile {
                largeFileBanner
                Divider()
            }

            TextEditorPane(
                text: Binding(
                    get: { session.text ?? "" },
                    set: { session.text = $0 }
                ),
                languageID: session.classification.isLargeFile
                    ? "plaintext"
                    : languageID,
                encodingName: session.metadata?.encoding.displayName ?? "UTF-8",
                lineEndingName: lineEndingName,
                fileSize: boundedInt64(
                    session.classification.totalByteCount
                ),
                canEdit: session.classification.isEditable,
                isEditing: Binding(
                    get: { session.isEditing },
                    set: { shouldEdit in
                        requestEditing(shouldEdit)
                    }
                ),
                wordWrap: session.classification.isLargeFile
                    ? .constant(false)
                    : $wordWrap,
                fontSize: $fontSize,
                onSave: {
                    guard session.isDirty else { return }
                    Task { _ = await save() }
                },
                isDirty: session.isDirty,
                initialEditorState: initialEditorState,
                onEditorStateChange: onEditorStateChange
            )
        }
    }

    private var largeFileBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye")
            Text(
                "Large file — showing the first "
                + formattedByteCount(UInt64(session.originalBytes.count))
                + " of "
                + formattedByteCount(session.classification.totalByteCount)
                + ". Editing, highlighting, wrapping, Reader, and outline are disabled."
            )
            Spacer(minLength: 0)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityElement(children: .combine)
    }

    private var lineEndingName: String {
        guard let lineEndings = session.metadata?.lineEndings else {
            return "—"
        }
        return switch lineEndings {
        case .none:
            "No line endings"
        case .lf:
            "LF"
        case .crlf:
            "CRLF"
        case .cr:
            "CR"
        case .mixed:
            "Mixed endings"
        }
    }

    private func requestEditing(_ shouldEdit: Bool) {
        if shouldEdit {
            guard session.classification.isEditable else { return }
            session.beginEditing()
            viewMode = .source
            onPin()
        } else if session.isDirty {
            showingDonePrompt = true
        } else {
            session.endEditing()
        }
    }

    @discardableResult
    private func save(
        overwriteExternalChanges: Bool = false
    ) async -> Bool {
        guard !isSaving else { return false }

        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await registry.save(
                session,
                overwriteExternalChanges: overwriteExternalChanges
            )
            lastFileStamp = WorkspaceFileStamp(url: session.url)
            return true
        } catch let error as FileIOError {
            if case .externalModification = error {
                showingSaveConflict = true
            } else {
                saveError = error.localizedDescription
            }
        } catch {
            saveError = error.localizedDescription
        }
        return false
    }

    private func saveCopy() async {
        guard session.text != nil,
              let metadata = session.metadata else {
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue =
            session.url.deletingPathExtension().lastPathComponent
            + " copy"
            + (session.url.pathExtension.isEmpty
                ? ""
                : ".\(session.url.pathExtension)")
        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }
        guard destination.standardizedFileURL != session.url.standardizedFileURL else {
            saveError = "Choose a different file for the copy."
            return
        }

        do {
            let bytes = try session.encodedCurrentText()
            _ = try await registry.fileIO.save(
                data: bytes,
                to: destination,
                expectedFingerprint: nil,
                metadata: metadata
            )
            onOpenURL(destination)
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func reloadAfterConflict() async {
        await reload()
        lastFileStamp = WorkspaceFileStamp(url: session.url)
    }

    private func monitorExternalChanges() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let currentStamp = WorkspaceFileStamp(url: session.url)
            guard let currentStamp, currentStamp != lastFileStamp else {
                continue
            }

            if session.isDirty {
                showingSaveConflict = true
                lastFileStamp = currentStamp
            } else {
                await reload()
                lastFileStamp = WorkspaceFileStamp(url: session.url)
            }
        }
    }

    private func updateRecoverySnapshot() async {
        do {
            try await Task.sleep(for: .milliseconds(700))
        } catch {
            return
        }
        guard session.isDirty, let text = session.text else {
            try? await registry.fileIO.removeRecoverySnapshot(
                sessionID: session.id
            )
            return
        }
        _ = try? await registry.fileIO.writeRecoverySnapshot(
            sessionID: session.id,
            sourceURL: session.url,
            text: text
        )
    }

    private func showNativeFindInterface() {
        guard viewMode == .source else { return }
        NSApp.sendAction(
            #selector(NSTextView.performFindPanelAction(_:)),
            to: nil,
            from: NSNumber(value: NSTextFinder.Action.showFindInterface.rawValue)
        )
    }

    private func boundedInt(_ value: UInt64) -> Int {
        value > UInt64(Int.max) ? Int.max : Int(value)
    }

    private func boundedInt64(_ value: UInt64) -> Int64 {
        value > UInt64(Int64.max) ? Int64.max : Int64(value)
    }

    private func formattedByteCount(_ value: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: boundedInt64(value),
            countStyle: .file
        )
    }
}

private struct WorkspaceFileStamp: Equatable {
    let byteCount: Int?
    let modificationDate: Date?

    init?(url: URL) {
        guard let values = try? url.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else {
            return nil
        }
        byteCount = values.fileSize
        modificationDate = values.contentModificationDate
    }
}
