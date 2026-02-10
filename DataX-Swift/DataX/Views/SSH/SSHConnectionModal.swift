import SwiftUI

struct SSHConnectionModal: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let existing: SSHConnection?
    let onSave: (SSHConnection, String?) -> Void

    @State private var name = ""
    @State private var host = ""
    @State private var port: String = "22"
    @State private var username = ""
    @State private var authMethod: SSHAuthMethod = .key
    @State private var keyPath = ""
    @State private var password = ""
    @State private var defaultPath = ""
    @State private var timeoutSecs: String = "30"

    @State private var isTesting = false
    @State private var testResult: SSHTestResult?
    @State private var detectedKeys: [SSHKeyInfo] = []

    private var isValid: Bool {
        !name.isEmpty && !host.isEmpty && !username.isEmpty &&
        (UInt16(port) != nil) &&
        (authMethod != .password || !password.isEmpty) &&
        (authMethod != .key || !keyPath.isEmpty)
    }

    init(existing: SSHConnection?, onSave: @escaping (SSHConnection, String?) -> Void) {
        self.existing = existing
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "network")
                    .foregroundColor(.accentColor)
                Text(existing != nil ? "Edit Connection" : "New SSH Connection")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Connection name
                    formField("Name", icon: "tag") {
                        TextField("My Server", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Host & Port
                    HStack(spacing: 12) {
                        formField("Host", icon: "globe") {
                            TextField("192.168.1.100 or hostname", text: $host)
                                .textFieldStyle(.roundedBorder)
                        }

                        formField("Port", icon: "number") {
                            TextField("22", text: $port)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                        }
                    }

                    // Username
                    formField("Username", icon: "person") {
                        TextField("root", text: $username)
                            .textFieldStyle(.roundedBorder)
                    }

                    Divider()

                    // Auth method
                    formField("Authentication", icon: "lock.shield") {
                        Picker("", selection: $authMethod) {
                            ForEach(SSHAuthMethod.allCases) { method in
                                Label(method.displayName, systemImage: method.icon)
                                    .tag(method)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    // Auth details
                    switch authMethod {
                    case .key:
                        keyAuthSection
                    case .password:
                        formField("Password", icon: "lock.fill") {
                            SecureField("Enter password", text: $password)
                                .textFieldStyle(.roundedBorder)
                        }
                    case .agent:
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Will use your system SSH agent")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    // Default remote path
                    formField("Default Path (optional)", icon: "folder") {
                        TextField("/home/user or /", text: $defaultPath)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Timeout
                    formField("Timeout (seconds)", icon: "clock") {
                        TextField("30", text: $timeoutSecs)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }

                    // Test result
                    if let result = testResult {
                        testResultView(result)
                    }
                }
                .padding()
            }

            Divider()

            // Footer buttons
            HStack {
                // Test connection button
                Button {
                    testCurrentConnection()
                } label: {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                        Text("Testing...")
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("Test Connection")
                    }
                }
                .disabled(!isValid || isTesting)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(existing != nil ? "Save" : "Add Connection") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 520, height: 580)
        .onAppear {
            detectedKeys = SSHKeyManager.detectKeys()
            if let conn = existing {
                name = conn.name
                host = conn.host
                port = "\(conn.port)"
                username = conn.username
                authMethod = conn.authMethod
                keyPath = conn.keyPath ?? ""
                defaultPath = conn.defaultPath ?? ""
                timeoutSecs = "\(conn.timeoutSecs)"
                if conn.authMethod == .password {
                    password = SSHConnectionStore.getPassword(for: conn.id) ?? ""
                }
            } else if let defaultKey = detectedKeys.first {
                keyPath = defaultKey.path
            }
        }
    }

    // MARK: - Key Auth Section

    @ViewBuilder
    private var keyAuthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            formField("SSH Key", icon: "key") {
                HStack {
                    TextField("~/.ssh/id_ed25519", text: $keyPath)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/.ssh")
                        panel.showsHiddenFiles = true
                        if panel.runModal() == .OK, let url = panel.url {
                            keyPath = url.path
                        }
                    }
                }
            }

            // Detected keys
            if !detectedKeys.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Detected SSH Keys:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(detectedKeys) { key in
                        Button {
                            keyPath = key.path
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "key.fill")
                                    .font(.caption)
                                    .foregroundColor(keyPath == key.path ? .accentColor : .secondary)
                                Text(key.name)
                                    .font(.caption)
                                Text("(\(key.type.rawValue))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                if keyPath == key.path {
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
            }
        }
    }

    // MARK: - Test Result

    @ViewBuilder
    private func testResultView(_ result: SSHTestResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(result.success ? .green : .red)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.message)
                    .font(.caption)
                    .foregroundColor(result.success ? .primary : .red)

                if let info = result.serverInfo {
                    Text(info)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if let latency = result.latencyMs {
                    Text("\(latency)ms")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(result.success ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(6)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func formField<Content: View>(_ label: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            content()
        }
    }

    private func testCurrentConnection() {
        let conn = buildConnection()
        isTesting = true
        testResult = nil

        Task {
            let result = await SSHService().testConnection(conn)
            await MainActor.run {
                testResult = result
                isTesting = false
            }
        }
    }

    private func buildConnection() -> SSHConnection {
        SSHConnection(
            id: existing?.id ?? UUID().uuidString,
            name: name,
            host: host,
            port: UInt16(port) ?? 22,
            username: username,
            authMethod: authMethod,
            keyPath: authMethod == .key ? keyPath : nil,
            defaultPath: defaultPath.isEmpty ? nil : defaultPath,
            timeoutSecs: UInt32(timeoutSecs) ?? 30
        )
    }

    private func save() {
        let conn = buildConnection()
        onSave(conn, authMethod == .password ? password : nil)
        dismiss()
    }
}
