import AppKit
import SwiftUI

struct WorkspaceFileTree: View {
    @ObservedObject var store: WorkspaceStore

    @State private var prompt: WorkspaceItemPrompt?
    @State private var proposedName = ""
    @State private var trashTarget: URL?

    var body: some View {
        VStack(spacing: 0) {
            if let rootURL = store.rootURL {
                List {
                    Section {
                        WorkspaceTreeChildren(
                            store: store,
                            directory: rootURL,
                            prompt: $prompt,
                            proposedName: $proposedName,
                            trashTarget: $trashTarget
                        )
                    } header: {
                        Label(
                            rootURL.lastPathComponent,
                            systemImage: "folder.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .help(rootURL.path)
                    }
                }
                .listStyle(.sidebar)

                Divider()
                HStack {
                    Toggle(
                        "Show All Files",
                        isOn: $store.showAllFiles
                    )
                    .toggleStyle(.checkbox)
                    .font(.caption)

                    Spacer()

                    Menu {
                        Button("New File…") {
                            begin(.newFile(parent: rootURL))
                        }
                        Button("New Folder…") {
                            begin(.newFolder(parent: rootURL))
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("New workspace item")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            } else {
                ContentUnavailableView {
                    Label("No Folder Open", systemImage: "folder")
                } description: {
                    Text("Open a folder to browse its files.")
                }
            }
        }
        .alert(
            prompt?.title ?? "Workspace Item",
            isPresented: Binding(
                get: { prompt != nil },
                set: { if !$0 { prompt = nil } }
            )
        ) {
            TextField("Name", text: $proposedName)
            Button(prompt?.actionTitle ?? "Create") {
                performPrompt()
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                prompt = nil
            }
        } message: {
            Text(prompt?.message ?? "")
        }
        .confirmationDialog(
            "Move “\(trashTarget?.lastPathComponent ?? "this item")” to Trash?",
            isPresented: Binding(
                get: { trashTarget != nil },
                set: { if !$0 { trashTarget = nil } }
            )
        ) {
            Button("Move to Trash", role: .destructive) {
                if let trashTarget {
                    store.moveToTrash(trashTarget)
                }
                trashTarget = nil
            }
            Button("Cancel", role: .cancel) {
                trashTarget = nil
            }
        } message: {
            Text("The item can be recovered from the Trash.")
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .openPaneNewFile
            )
        ) { _ in
            guard let rootURL = store.rootURL else { return }
            begin(.newFile(parent: rootURL))
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .openPaneNewFolder
            )
        ) { _ in
            guard let rootURL = store.rootURL else { return }
            begin(.newFolder(parent: rootURL))
        }
    }

    private func begin(_ itemPrompt: WorkspaceItemPrompt) {
        prompt = itemPrompt
        proposedName = itemPrompt.initialName
    }

    private func performPrompt() {
        guard let prompt else { return }
        switch prompt {
        case .newFile(let parent):
            store.createFile(named: proposedName, in: parent)
        case .newFolder(let parent):
            store.createFolder(named: proposedName, in: parent)
        case .rename(let url):
            store.rename(url, to: proposedName)
        }
        self.prompt = nil
    }
}

private struct WorkspaceTreeChildren: View {
    @ObservedObject var store: WorkspaceStore
    let directory: URL
    @Binding var prompt: WorkspaceItemPrompt?
    @Binding var proposedName: String
    @Binding var trashTarget: URL?

    var body: some View {
        let entries = store.children(of: directory)
        if store.loadingDirectories.contains(directory.standardizedFileURL),
           entries.isEmpty {
            HStack {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Spacer()
            }
            .padding(.vertical, 6)
        } else if entries.isEmpty {
            Text("Empty")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(entries) { entry in
                if entry.isDirectory, !entry.isSymbolicLink {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { store.isExpanded(entry.url) },
                            set: {
                                store.setExpanded(
                                    entry.url,
                                    expanded: $0
                                )
                            }
                        )
                    ) {
                        WorkspaceTreeChildren(
                            store: store,
                            directory: entry.url,
                            prompt: $prompt,
                            proposedName: $proposedName,
                            trashTarget: $trashTarget
                        )
                    } label: {
                        WorkspaceTreeRow(
                            store: store,
                            entry: entry
                        )
                    }
                    .contextMenu {
                        contextMenu(for: entry)
                    }
                } else {
                    WorkspaceTreeRow(
                        store: store,
                        entry: entry
                    )
                    .contextMenu {
                        contextMenu(for: entry)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for entry: WorkspaceTreeEntry) -> some View {
        if entry.isDirectory, !entry.isSymbolicLink {
            Button("New File…") {
                begin(.newFile(parent: entry.url))
            }
            Button("New Folder…") {
                begin(.newFolder(parent: entry.url))
            }
            Divider()
        }

        if !entry.isDirectory {
            Button("Open to the Side") {
                store.createSplit()
                store.open(entry.url, behavior: .pinned, in: .secondary)
            }
            Divider()
        }

        Button("Rename…") {
            begin(.rename(url: entry.url))
        }
        Button("Duplicate") {
            store.duplicate(entry.url)
        }
        Button("Move…") {
            chooseMoveDestination(for: entry.url)
        }
        Divider()
        Button("Reveal in Finder") {
            store.revealInFinder(entry.url)
        }
        Button("Copy Path") {
            store.copyPath(entry.url)
        }
        Divider()
        Button("Move to Trash", role: .destructive) {
            trashTarget = entry.url
        }
    }

    private func begin(_ itemPrompt: WorkspaceItemPrompt) {
        prompt = itemPrompt
        proposedName = itemPrompt.initialName
    }

    private func chooseMoveDestination(for url: URL) {
        let panel = NSOpenPanel()
        panel.title = "Move “\(url.lastPathComponent)”"
        panel.prompt = "Move"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.rootURL

        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }
        store.move(url, to: destination)
    }
}

private struct WorkspaceTreeRow: View {
    @ObservedObject var store: WorkspaceStore
    let entry: WorkspaceTreeEntry
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var isSelected: Bool {
        store.selectedURL?.standardizedFileURL == entry.url.standardizedFileURL
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 16)
            Text(entry.name)
                .lineLimit(1)
                .truncationMode(.middle)
            if entry.isSymbolicLink {
                Image(systemName: "arrow.turn.up.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(
                            colorSchemeContrast == .increased ? 0.3 : 0.14
                        )
                        : .clear
                )
                .padding(.horizontal, -4)
        )
        .onTapGesture(count: 2) {
            if entry.isDirectory {
                if !entry.isSymbolicLink {
                    store.setExpanded(
                        entry.url,
                        expanded: !store.isExpanded(entry.url)
                    )
                }
            } else {
                store.open(entry.url, behavior: .pinned)
            }
        }
        .onTapGesture(count: 1) {
            guard !entry.isDirectory else { return }
            store.open(entry.url, behavior: .preview)
        }
        .focusable()
        .onKeyPress(.return) {
            activateFromKeyboard()
            return .handled
        }
        .onKeyPress(.space) {
            activateFromKeyboard()
            return .handled
        }
        .help(entry.url.path)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            entry.isDirectory ? "\(entry.name), folder" : entry.name
        )
        .accessibilityAction {
            activateFromKeyboard()
        }
    }

    private var iconName: String {
        if entry.isDirectory {
            return store.isExpanded(entry.url) ? "folder.fill" : "folder"
        }

        switch entry.url.pathExtension.lowercased() {
        case "md", "markdown":
            return "text.document"
        case "pdf":
            return "doc.richtext"
        case "json", "jsonc":
            return "curlybraces"
        case "py":
            return "chevron.left.forwardslash.chevron.right"
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "svg":
            return "photo"
        default:
            return "doc"
        }
    }

    private var iconColor: Color {
        entry.isDirectory ? .accentColor : .secondary
    }

    private func activateFromKeyboard() {
        if entry.isDirectory {
            guard !entry.isSymbolicLink else { return }
            store.setExpanded(
                entry.url,
                expanded: !store.isExpanded(entry.url)
            )
        } else {
            store.open(entry.url, behavior: .preview)
        }
    }
}

enum WorkspaceItemPrompt: Identifiable {
    case newFile(parent: URL)
    case newFolder(parent: URL)
    case rename(url: URL)

    var id: String {
        switch self {
        case .newFile(let parent):
            "file:\(parent.path)"
        case .newFolder(let parent):
            "folder:\(parent.path)"
        case .rename(let url):
            "rename:\(url.path)"
        }
    }

    var title: String {
        switch self {
        case .newFile:
            "New File"
        case .newFolder:
            "New Folder"
        case .rename:
            "Rename"
        }
    }

    var actionTitle: String {
        switch self {
        case .newFile, .newFolder:
            "Create"
        case .rename:
            "Rename"
        }
    }

    var message: String {
        switch self {
        case .newFile:
            "Create an empty file in this folder."
        case .newFolder:
            "Create a folder in this location."
        case .rename:
            "Enter a new name for this item."
        }
    }

    var initialName: String {
        switch self {
        case .newFile:
            "untitled.txt"
        case .newFolder:
            "untitled folder"
        case .rename(let url):
            url.lastPathComponent
        }
    }
}
