import SwiftUI

@main
struct DataXApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Folder...") {
                    appState.showFolderPicker = true
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Refresh") {
                    appState.refresh()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.scannerViewModel.rootNode == nil)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
