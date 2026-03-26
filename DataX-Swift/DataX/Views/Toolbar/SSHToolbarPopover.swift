import SwiftUI

struct SSHToolbarPopoverButton: View {
    @Environment(AppState.self) private var appState
    @State private var isPopoverPresented = false

    var body: some View {
        Button {
            isPopoverPresented.toggle()
        } label: {
            Image(systemName: "network")
        }
        .help("SSH Connections")
        .popover(
            isPresented: $isPopoverPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            SSHToolbarPopover {
                isPopoverPresented = false
            }
        }
        .sheet(isPresented: Binding(
            get: {
                appState.sshViewModel.showConnectionModal &&
                appState.scannerViewModel.rootNode != nil &&
                !appState.scannerViewModel.isScanning
            },
            set: { appState.sshViewModel.showConnectionModal = $0 }
        )) {
            SSHConnectionModal(existing: appState.sshViewModel.editingConnection) { connection, password in
                appState.sshViewModel.saveConnection(connection, password: password)
            }
        }
    }
}

struct SSHToolbarPopover: View {
    let dismissPopover: () -> Void

    var body: some View {
        SSHConnectionsList(dismissPopover: dismissPopover)
            .padding(16)
            .frame(width: 420)
    }
}
