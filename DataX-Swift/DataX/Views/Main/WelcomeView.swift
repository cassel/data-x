import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var appState
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 24) {
            Spacer(minLength: 24)

            dropZone

            VStack(spacing: 10) {
                ForEach(state.sshViewModel.welcomeScreenRecentConnections) { connection in
                    WelcomeConnectionRow(connection: connection)
                }

                Button {
                    state.sshViewModel.addNewConnection()
                } label: {
                    Label("Connect to Server", systemImage: "network")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: 320)

            Spacer(minLength: 24)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .dropDestination(for: URL.self) { urls, _ in
            state.handleFolderIntake(urls)
        } isTargeted: { isTargeted in
            self.isDropTargeted = isTargeted
        }
        .sheet(isPresented: Binding(
            get: { state.sshViewModel.showConnectionModal && state.scannerViewModel.rootNode == nil },
            set: { state.sshViewModel.showConnectionModal = $0 }
        )) {
            SSHConnectionModal(existing: state.sshViewModel.editingConnection) { connection, password in
                state.sshViewModel.saveConnection(connection, password: password)
            }
        }
    }

    private var dropZone: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(isDropTargeted ? 0.18 : 0.09))
                .overlay {
                    Circle()
                        .strokeBorder(
                            Color.accentColor.opacity(isDropTargeted ? 0.82 : 0.42),
                            lineWidth: isDropTargeted ? 3 : 2
                        )
                }
                .phaseAnimator([false, true]) { content, phase in
                    content
                        .scaleEffect(isDropTargeted ? 1.02 : (phase ? 1.04 : 0.96))
                        .opacity(isDropTargeted ? 1.0 : (phase ? 1.0 : 0.9))
                        .shadow(
                            color: Color.accentColor.opacity(isDropTargeted ? 0.24 : (phase ? 0.16 : 0.08)),
                            radius: isDropTargeted ? 28 : (phase ? 24 : 14)
                        )
                } animation: { _ in
                    .easeInOut(duration: 2.2)
                }
                .frame(width: 300, height: 300)

            Text("Drop a folder")
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WelcomeConnectionRow: View {
    @Environment(AppState.self) private var appState

    let connection: SSHConnection

    var body: some View {
        @Bindable var state = appState

        HStack(spacing: 0) {
            Button {
                state.sshViewModel.connect(connection, scannerVM: state.scannerViewModel)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "network")
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(connection.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text("\(connection.username)@\(connection.host)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: connection.authMethod.icon)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Button {
                state.sshViewModel.editConnection(connection)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .help("Edit Connection")
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contextMenu {
            Button {
                state.sshViewModel.connect(connection, scannerVM: state.scannerViewModel)
            } label: {
                Label("Connect & Scan", systemImage: "play.fill")
            }

            Button {
                state.sshViewModel.editConnection(connection)
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                state.sshViewModel.deleteConnection(connection.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
