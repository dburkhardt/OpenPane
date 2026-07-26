import AppKit
import SwiftUI

extension FocusedValues {
    @Entry var workspaceStore: WorkspaceStore?
}

extension Notification.Name {
    static let openPaneQuickOpen = Notification.Name("OpenPane.QuickOpen")
    static let openPaneNewFile = Notification.Name("OpenPane.NewFile")
    static let openPaneNewFolder = Notification.Name("OpenPane.NewFolder")
    static let openPaneSave = Notification.Name("OpenPane.Save")
    static let openPaneToggleEditing = Notification.Name("OpenPane.ToggleEditing")
    static let openPaneFind = Notification.Name("OpenPane.Find")
}

struct OpenPaneCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.workspaceStore) private var store

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New File…") {
                NotificationCenter.default.post(
                    name: .openPaneNewFile,
                    object: nil
                )
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(store?.rootURL == nil)

            Button("New Folder…") {
                NotificationCenter.default.post(
                    name: .openPaneNewFolder,
                    object: nil
                )
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(store?.rootURL == nil)

            Divider()

            Button("Open File…") {
                openFile()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button("Open Folder…") {
                openFolder()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                NotificationCenter.default.post(
                    name: .openPaneSave,
                    object: nil
                )
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(store?.selectedURL == nil)
        }

        CommandMenu("Navigate") {
            Button("Quick Open…") {
                NotificationCenter.default.post(
                    name: .openPaneQuickOpen,
                    object: nil
                )
            }
            .keyboardShortcut("p", modifiers: [.command])
            .disabled(store?.rootURL == nil)

            Button("Reveal in Finder") {
                if let url = store?.selectedURL {
                    store?.revealInFinder(url)
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(store?.selectedURL == nil)

            Button("Copy Path") {
                if let url = store?.selectedURL {
                    store?.copyPath(url)
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(store?.selectedURL == nil)
        }

        CommandMenu("Editor") {
            Button("Edit") {
                NotificationCenter.default.post(
                    name: .openPaneToggleEditing,
                    object: nil
                )
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(store?.selectedURL == nil)

            Button("Find…") {
                NotificationCenter.default.post(
                    name: .openPaneFind,
                    object: nil
                )
            }
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(store?.selectedURL == nil)

            Divider()

            Button("Split Right") {
                store?.createSplit(axis: .horizontal)
            }
            .keyboardShortcut("\\", modifiers: [.command])

            Button("Split Down") {
                store?.createSplit(axis: .vertical)
            }
            .keyboardShortcut("\\", modifiers: [.command, .shift])

            Button("Move File to Other Group") {
                store?.moveSelectedTabToOtherPane()
            }
            .disabled(store?.selectedURL == nil)

            Button("Close Editor Group") {
                store?.closeSplit()
            }
            .disabled(store?.secondaryPane == nil)
        }

        CommandMenu("Workspace") {
            Toggle(
                "Show All Files",
                isOn: Binding(
                    get: { store?.showAllFiles ?? false },
                    set: { store?.showAllFiles = $0 }
                )
            )
            .disabled(store?.rootURL == nil)
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.title = "Open File"
        panel.prompt = "Open"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard !OpenPaneWindowRegistry.shared.activateIfOpen(url) else {
            return
        }
        openWindow(id: "content", value: WorkspaceLaunch.file(url))
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.title = "Open Folder"
        panel.prompt = "Open"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openWindow(id: "content", value: WorkspaceLaunch.folder(url))
    }
}
