import SwiftUI

struct SSHSidebarSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var ssh = appState.sshViewModel

        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    ssh.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(ssh.isExpanded ? 90 : 0))

                    Image(systemName: "network")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("SSH Connections")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    Spacer()

                    // Add button
                    Button {
                        ssh.addNewConnection()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Add SSH Connection")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            // Connection list
            if ssh.isExpanded {
                if ssh.connections.isEmpty {
                    emptyState
                } else {
                    ForEach(ssh.connections) { connection in
                        connectionRow(connection)
                    }
                }
            }
        }
        .sheet(isPresented: $ssh.showConnectionModal) {
            SSHConnectionModal(existing: ssh.editingConnection) { conn, password in
                ssh.saveConnection(conn, password: password)
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No connections")
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                appState.sshViewModel.addNewConnection()
            } label: {
                Label("Add Server", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Connection Row

    @ViewBuilder
    private func connectionRow(_ connection: SSHConnection) -> some View {
        let isConnecting = appState.sshViewModel.connectingId == connection.id
        let isTesting = appState.sshViewModel.testingConnectionId == connection.id

        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(isConnecting ? Color.orange : Color.secondary.opacity(0.3))
                .frame(width: 6, height: 6)

            // Connection info
            VStack(alignment: .leading, spacing: 1) {
                Text(connection.name)
                    .font(.system(size: 12))
                    .lineLimit(1)

                Text("\(connection.username)@\(connection.host)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Auth method icon
            Image(systemName: connection.authMethod.icon)
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            // Activity indicator
            if isConnecting || isTesting {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 12, height: 12)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            appState.sshViewModel.connect(connection, scannerVM: appState.scannerViewModel)
        }
        .onTapGesture(count: 1) {
            // Single tap does nothing for now, keeps double-tap working
        }
        .contextMenu {
            Button {
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
