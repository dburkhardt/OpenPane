import AppKit
import OpenPaneCore
import SwiftUI

struct WorkspacePaneView: View {
    @ObservedObject var store: WorkspaceStore
    let paneID: WorkspacePaneID
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var paneState: WorkspacePaneState {
        store.pane(paneID)
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceTabBar(store: store, paneID: paneID)
            Divider()

            if let tab = paneState.selectedTab {
                WorkspaceDocumentView(
                    registry: store.documents,
                    fileURL: tab.url,
                    isPinned: tab.isPinned,
                    isActive: store.activePane == paneID,
                    initialViewModeRawValue: tab.viewModeRawValue,
                    initialEditorState: tab.editorState,
                    onPin: {
                        store.pin(tab.id, in: paneID)
                    },
                    onViewModeChange: { rawValue in
                        store.updateViewMode(
                            rawValue,
                            for: tab.id,
                            in: paneID
                        )
                    },
                    onEditorStateChange: { editorState in
                        store.updateEditorState(
                            editorState,
                            for: tab.id,
                            in: paneID
                        )
                    },
                    onOpenURL: { url in
                        if store.secondaryPane == nil {
                            store.createSplit()
                        }
                        store.open(
                            url,
                            behavior: .pinned,
                            in: .secondary
                        )
                    },
                    onPreviewToSide: {
                        let destination: WorkspacePaneID =
                            paneID == .primary ? .secondary : .primary
                        if destination == .secondary,
                           store.secondaryPane == nil {
                            store.createSplit(axis: .horizontal)
                        }
                        store.open(
                            tab.url,
                            behavior: .pinned,
                            in: destination
                        )
                        if let destinationTabID =
                            store.pane(destination).selectedTabID {
                            store.updateViewMode(
                                FileViewMode.reader.rawValue,
                                for: destinationTabID,
                                in: destination
                            )
                        }
                    }
                )
                .id(tab.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                WorkspaceEmptyPane(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if store.activePane == paneID, store.secondaryPane != nil {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(
                        Color.accentColor.opacity(
                            colorSchemeContrast == .increased ? 1 : 0.45
                        ),
                        lineWidth: colorSchemeContrast == .increased ? 2 : 1
                    )
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                store.activePane = paneID
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            paneID == .primary ? "Primary editor group" : "Secondary editor group"
        )
    }
}

private struct WorkspaceTabBar: View {
    @ObservedObject var store: WorkspaceStore
    let paneID: WorkspacePaneID

    private var paneState: WorkspacePaneState {
        store.pane(paneID)
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(paneState.tabs) { tab in
                    WorkspaceTabButton(
                        tab: tab,
                        isSelected: paneState.selectedTabID == tab.id,
                        select: {
                            store.select(tab.id, in: paneID)
                        },
                        pin: {
                            store.pin(tab.id, in: paneID)
                        },
                        close: {
                            store.close(tab.id, in: paneID)
                        },
                        moveToOtherPane: {
                            store.select(tab.id, in: paneID)
                            store.moveSelectedTabToOtherPane()
                        }
                    )
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(height: 34)
        .background(.bar)
    }
}

private struct WorkspaceTabButton: View {
    let tab: WorkspaceTab
    let isSelected: Bool
    let select: () -> Void
    let pin: () -> Void
    let close: () -> Void
    let moveToOtherPane: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: fileIcon)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(tab.title)
                .font(.caption)
                .italic(!tab.isPinned)
                .lineLimit(1)
                .truncationMode(.middle)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovering || isSelected ? 1 : 0)
            .accessibilityLabel("Close \(tab.title)")
        }
        .padding(.horizontal, 9)
        .frame(minWidth: 100, maxWidth: 190, minHeight: 34)
        .background(
            isSelected
                ? Color(nsColor: .textBackgroundColor)
                : Color.clear
        )
        .overlay(alignment: .trailing) {
            Divider()
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            pin()
        }
        .onTapGesture(count: 1) {
            select()
        }
        .onHover { isHovering = $0 }
        .focusable()
        .onKeyPress(.return) {
            select()
            return .handled
        }
        .onKeyPress(.space) {
            select()
            return .handled
        }
        .contextMenu {
            if !tab.isPinned {
                Button("Keep Open") {
                    pin()
                }
            }
            Button("Move to Other Group") {
                moveToOtherPane()
            }
            Divider()
            Button("Close") {
                close()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(tab.title), \(tab.isPinned ? "pinned tab" : "preview tab")"
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction {
            select()
        }
        .accessibilityAction(named: Text("Keep Open")) {
            pin()
        }
        .accessibilityAction(named: Text("Move to Other Group")) {
            moveToOtherPane()
        }
        .accessibilityAction(named: Text("Close")) {
            close()
        }
        .help(tab.isPinned ? tab.url.path : "\(tab.url.path) — Preview")
    }

    private var fileIcon: String {
        switch tab.url.pathExtension.lowercased() {
        case "md", "markdown":
            "text.document"
        case "pdf":
            "doc.richtext"
        case "json", "jsonc":
            "curlybraces"
        default:
            "doc"
        }
    }
}

private struct WorkspaceEmptyPane: View {
    @ObservedObject var store: WorkspaceStore

    var body: some View {
        ContentUnavailableView {
            Label("No File Open", systemImage: "doc.text")
        } description: {
            if store.rootURL == nil {
                Text("Open a file or folder to begin.")
            } else {
                Text("Select a file in the sidebar or press ⌘P.")
            }
        } actions: {
            if store.rootURL == nil {
                HStack {
                    Button("Open File…") {
                        openFile()
                    }
                    Button("Open Folder…") {
                        openFolder()
                    }
                }
            }
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.title = "Open File"
        panel.prompt = "Open"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.openLooseFile(url)
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.title = "Open Folder"
        panel.prompt = "Open"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.openFolder(url)
    }
}
