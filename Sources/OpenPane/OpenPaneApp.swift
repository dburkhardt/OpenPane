import SwiftUI

@main
struct OpenPaneApp: App {
    @NSApplicationDelegateAdaptor(OpenPaneAppDelegate.self)
    private var appDelegate

    var body: some Scene {
        WindowGroup(
            "OpenPane",
            id: "content",
            for: WorkspaceLaunch.self
        ) { launch in
            WorkspaceView(launch: launch.wrappedValue)
        } defaultValue: {
            .restore
        }
        .defaultSize(width: 1_120, height: 740)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
            OpenPaneCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
