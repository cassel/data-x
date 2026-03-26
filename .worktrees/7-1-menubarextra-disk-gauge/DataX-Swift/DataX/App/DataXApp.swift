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
            CommandGroup(replacing: .appInfo) {
                AboutCommand()
            }
            CommandGroup(replacing: .newItem) {
                Button("Open Folder...") {
                    appState.showFolderPicker = true
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("Connect to Server...") {
                    appState.sshViewModel.addNewConnection()
                }
                .keyboardShortcut("k", modifiers: .command)

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

        Window("About DataX", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

struct AboutCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About DataX") {
            openWindow(id: "about")
        }
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)

            Text("DataX")
                .font(.system(size: 24, weight: .bold))

            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Disk Space Analyzer")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()
                .frame(width: 200)

            VStack(spacing: 4) {
                Text("Developed by C. Cassel")
                    .font(.subheadline)

                Link("c@cassel.us", destination: URL(string: "mailto:c@cassel.us")!)
                    .font(.subheadline)

                Link("www.cassel.us/apps", destination: URL(string: "https://www.cassel.us/apps")!)
                    .font(.subheadline)
            }

            Spacer()
                .frame(height: 8)
        }
        .padding(32)
        .frame(width: 300, height: 340)
    }
}
