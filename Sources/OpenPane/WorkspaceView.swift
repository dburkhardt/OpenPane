import AppKit
import SwiftUI

@MainActor
struct WorkspaceView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var store: WorkspaceStore
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showingQuickOpen = false

    init(launch: WorkspaceLaunch = .restore) {
        _store = StateObject(
            wrappedValue: WorkspaceStore(launch: launch)
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            WorkspaceFileTree(store: store)
                .navigationSplitViewColumnWidth(
                    min: 190,
                    ideal: 245,
                    max: 380
                )
        } detail: {
            editorGroups
        }
        .navigationTitle(store.displayName)
        .focusedSceneValue(\.workspaceStore, store)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if store.rootURL != nil {
                    Button {
                        showingQuickOpen = true
                    } label: {
                        Label("Quick Open", systemImage: "doc.text.magnifyingglass")
                    }
                    .keyboardShortcut("p", modifiers: [.command])
                    .help("Quick Open (⌘P)")
                }

                Menu {
                    Button {
                        store.createSplit(axis: .horizontal)
                    } label: {
                        Label("Split Right", systemImage: "rectangle.split.2x1")
                    }

                    Button {
                        store.createSplit(axis: .vertical)
                    } label: {
                        Label("Split Down", systemImage: "rectangle.split.1x2")
                    }

                    if store.secondaryPane != nil {
                        Divider()
                        Picker("Split Layout", selection: $store.splitAxis) {
                            ForEach(WorkspaceSplitAxis.allCases) { axis in
                                Label(axis.label, systemImage: axis.systemImage)
                                    .tag(axis)
                            }
                        }
                        Divider()
                        Button("Close Editor Group") {
                            store.closeSplit()
                        }
                    }
                } label: {
                    Label("Editor Layout", systemImage: "rectangle.split.2x1")
                }
                .help("Editor Layout")
            }
        }
        .sheet(isPresented: $showingQuickOpen) {
            QuickOpenView(
                store: store,
                isPresented: $showingQuickOpen
            )
        }
        .alert(
            "OpenPane",
            isPresented: Binding(
                get: { store.operationError != nil },
                set: { if !$0 { store.operationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                store.operationError = nil
            }
        } message: {
            Text(store.operationError ?? "")
        }
        .alert(
            "Save Changes to “\(store.pendingTabClose?.url.lastPathComponent ?? "File")”?",
            isPresented: Binding(
                get: { store.pendingTabClose != nil },
                set: { if !$0 { store.cancelPendingTabClose() } }
            )
        ) {
            Button("Save") {
                Task { await store.saveAndClosePendingTab() }
            }
            Button("Discard Changes", role: .destructive) {
                Task { await store.discardAndClosePendingTab() }
            }
            Button("Cancel", role: .cancel) {
                store.cancelPendingTabClose()
            }
        } message: {
            Text("OpenPane never saves over a source file automatically.")
        }
        .alert(
            "Recovered Edits Available",
            isPresented: Binding(
                get: { !store.pendingRecoverySnapshotURLs.isEmpty },
                set: { if !$0 { store.dismissRecoveryOffer() } }
            )
        ) {
            Button("Open Recovery Copies") {
                store.openRecoverySnapshots()
            }
            Button("Reveal in Finder") {
                store.revealRecoverySnapshots()
            }
            Button("Later", role: .cancel) {
                store.dismissRecoveryOffer()
            }
        } message: {
            let count = store.pendingRecoverySnapshotURLs.count
            Text(
                count == 1
                    ? "OpenPane found one recovery copy from an earlier editing session. It will never overwrite the source file."
                    : "OpenPane found \(count) recovery copies from earlier editing sessions. They will never overwrite source files."
            )
        }
        .background {
            WorkspaceWindowAccessor { window in
                OpenPaneWindowRegistry.shared.register(
                    window: window,
                    store: store,
                    openWindow: { launch in
                        openWindow(id: "content", value: launch)
                    }
                )
            }
        }
        .onAppear {
            store.start()
            if store.rootURL == nil {
                columnVisibility = .detailOnly
            }
        }
        .onDisappear {
            OpenPaneWindowRegistry.shared.unregister(store: store)
        }
        .onChange(of: store.rootURL) { _, rootURL in
            columnVisibility = rootURL == nil ? .detailOnly : .all
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .openPaneQuickOpen
            )
        ) { _ in
            if store.rootURL != nil {
                showingQuickOpen = true
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .frame(minWidth: 780, minHeight: 520)
    }

    @ViewBuilder
    private var editorGroups: some View {
        if store.secondaryPane != nil {
            switch store.splitAxis {
            case .horizontal:
                HSplitView {
                    WorkspacePaneView(store: store, paneID: .primary)
                        .frame(minWidth: 320)
                    WorkspacePaneView(store: store, paneID: .secondary)
                        .frame(minWidth: 320)
                }
            case .vertical:
                VSplitView {
                    WorkspacePaneView(store: store, paneID: .primary)
                        .frame(minHeight: 220)
                    WorkspacePaneView(store: store, paneID: .secondary)
                        .frame(minHeight: 220)
                }
            }
        } else {
            WorkspacePaneView(store: store, paneID: .primary)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier("public.file-url")
        }
        guard !fileProviders.isEmpty else { return false }

        for provider in fileProviders {
            provider.loadItem(
                forTypeIdentifier: "public.file-url",
                options: nil
            ) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                guard let url else { return }

                Task { @MainActor in
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(
                        atPath: url.path,
                        isDirectory: &isDirectory
                    ) else {
                        return
                    }

                    if isDirectory.boolValue {
                        if store.rootURL == nil,
                           store.primaryPane.tabs.isEmpty {
                            store.openFolder(url)
                        } else {
                            openWindow(
                                id: "content",
                                value: WorkspaceLaunch.folder(url)
                            )
                        }
                    } else if store.rootURL == nil,
                              store.primaryPane.tabs.isEmpty {
                        store.openLooseFile(url)
                    } else if let rootURL = store.rootURL,
                              url.standardizedFileURL.path.hasPrefix(
                                rootURL.standardizedFileURL.path + "/"
                              ) {
                        store.open(url, behavior: .pinned)
                    } else {
                        if !OpenPaneWindowRegistry.shared.activateIfOpen(url) {
                            openWindow(
                                id: "content",
                                value: WorkspaceLaunch.file(url)
                            )
                        }
                    }
                }
            }
        }
        return true
    }
}
