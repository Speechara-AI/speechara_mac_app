import SwiftUI

@main
struct SpeecharaApp: App {
    @StateObject private var authStore = AuthSessionStore()

    var body: some Scene {
        WindowGroup("Speechara") {
            SpeecharaRootView()
                .environmentObject(authStore)
        }
        .commands {
            SpeecharaFileCommands()
        }

        Window("Settings", id: "speechara-settings") {
            SpeecharaSettingsView()
                .environmentObject(authStore)
        }
        .windowResizability(.contentSize)
    }
}

private struct SpeecharaFileCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()

            Button("Settings...") {
                openWindow(id: "speechara-settings")
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                openWindow(id: "speechara-settings")
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }
}
