import SwiftUI

@main
struct FreeMarkApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { configuration in
            WorkspaceView(
                document: configuration.$document,
                fileURL: configuration.fileURL
            )
        }
        .commands {
            SidebarCommands()
            TextEditingCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
