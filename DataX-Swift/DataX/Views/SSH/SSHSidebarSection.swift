import SwiftUI

struct SSHConnectionsList: View {
    @Environment(AppState.self) private var appState
    let dismissPopover: () -> Void

    var body: some View {
        @Bindable var ssh = appState.sshViewModel

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("SSH Connections", systemImage: "network")
                    .font(.headline)

                Spacer()

                Button {
                    dismissPopover()
                    ssh.addNewConnection()
                } label: {
                    Label("Add Server", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.bottom, 12)

            if ssh.connections.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(ssh.connections) { connection in
                            connectionRow(connection)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 320)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("No saved connections")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button {
                dismissPopover()
                appState.sshViewModel.addNewConnection()
            } label: {
                Label("Add Server", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private func connectionRow(_ connection: SSHConnection) -> some View {
        let isConnecting = appState.sshViewModel.connectingId == connection.id
        let isTesting = appState.sshViewModel.testingConnectionId == connection.id

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isConnecting ? Color.orange : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)

                    Text("\(connection.username)@\(connection.host)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: connection.authMethod.icon)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 6) {
                Button {
                    dismissPopover()
                    appState.sshViewModel.connect(connection, scannerVM: appState.scannerViewModel)
                } label: {
                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Label("Connect", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(appState.sshViewModel.isConnecting && !isConnecting)

                Button {
                    appState.sshViewModel.testConnection(connection)
                } label: {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Label("Test", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: 0)

                Button {
                    dismissPopover()
                    appState.sshViewModel.editConnection(connection)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit Connection")

                Button(role: .destructive) {
                    appState.sshViewModel.deleteConnection(connection.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete Connection")
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(count: 2) {
            dismissPopover()
            appState.sshViewModel.connect(connection, scannerVM: appState.scannerViewModel)
        }
        .contextMenu {
            Button {
                dismissPopover()
                appState.sshViewModel.connect(connection, scannerVM: appState.scannerViewModel)
            } label: {
                Label("Connect & Scan", systemImage: "play.fill")
            }

            Button {
                appState.sshViewModel.testConnection(connection)
            } label: {
                Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
            }

            Divider()

            Button {
                dismissPopover()
                appState.sshViewModel.editConnection(connection)
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                appState.sshViewModel.deleteConnection(connection.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
