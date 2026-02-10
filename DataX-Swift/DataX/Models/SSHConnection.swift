import Foundation

// MARK: - Auth Method

enum SSHAuthMethod: String, Codable, CaseIterable, Identifiable {
    case key = "key"
    case password = "password"
    case agent = "agent"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .key: return "SSH Key"
        case .password: return "Password"
        case .agent: return "SSH Agent"
        }
    }

    var icon: String {
        switch self {
        case .key: return "key.fill"
        case .password: return "lock.fill"
        case .agent: return "person.badge.key.fill"
        }
    }
}

// MARK: - SSH Connection

struct SSHConnection: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var host: String
    var port: UInt16
    var username: String
    var authMethod: SSHAuthMethod
    var keyPath: String?
    var defaultPath: String?
    var timeoutSecs: UInt32
    var createdAt: Int64
    var lastUsedAt: Int64?

    init(
        id: String = UUID().uuidString,
        name: String,
        host: String,
        port: UInt16 = 22,
        username: String,
        authMethod: SSHAuthMethod = .key,
        keyPath: String? = nil,
        defaultPath: String? = nil,
        timeoutSecs: UInt32 = 30
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.keyPath = keyPath
        self.defaultPath = defaultPath
        self.timeoutSecs = timeoutSecs
        self.createdAt = Int64(Date().timeIntervalSince1970)
        self.lastUsedAt = nil
    }

    // MARK: - Codable (compatible with Tauri JSON format)

    enum CodingKeys: String, CodingKey {
        case id, name, host, port, username
        case authMethod = "auth_method"
        case keyPath = "key_path"
        case defaultPath = "default_path"
        case timeoutSecs = "timeout_secs"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
    }

    // Custom decoding to handle Tauri's tagged auth_method format
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(UInt16.self, forKey: .port)
        username = try container.decode(String.self, forKey: .username)
        defaultPath = try container.decodeIfPresent(String.self, forKey: .defaultPath)
        timeoutSecs = try container.decode(UInt32.self, forKey: .timeoutSecs)
        createdAt = try container.decode(Int64.self, forKey: .createdAt)
        lastUsedAt = try container.decodeIfPresent(Int64.self, forKey: .lastUsedAt)

        // Handle Tauri's tagged union format: {"type": "key", "key_path": "..."}
        if let authObj = try? container.decode(TauriAuthMethod.self, forKey: .authMethod) {
            authMethod = authObj.method
            if case .key = authMethod {
                keyPath = authObj.keyPath ?? keyPath
            }
        } else {
            // Simple string format
            authMethod = try container.decode(SSHAuthMethod.self, forKey: .authMethod)
            keyPath = try container.decodeIfPresent(String.self, forKey: .keyPath)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(username, forKey: .username)
        // Encode auth_method as Tauri-compatible tagged format
        let tauriAuth = TauriAuthMethod(method: authMethod, keyPath: keyPath)
        try container.encode(tauriAuth, forKey: .authMethod)
        try container.encodeIfPresent(defaultPath, forKey: .defaultPath)
        try container.encode(timeoutSecs, forKey: .timeoutSecs)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
    }
}

// MARK: - Tauri Compatibility

/// Handles Tauri's tagged union auth method format
private struct TauriAuthMethod: Codable {
    let method: SSHAuthMethod
    let keyPath: String?

    enum CodingKeys: String, CodingKey {
        case type
        case keyPath = "key_path"
    }

    init(method: SSHAuthMethod, keyPath: String?) {
        self.method = method
        self.keyPath = keyPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "key": method = .key
        case "password": method = .password
        case "agent": method = .agent
        default: method = .key
        }
        keyPath = try container.decodeIfPresent(String.self, forKey: .keyPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(method.rawValue, forKey: .type)
        if case .key = method, let keyPath {
            try container.encode(keyPath, forKey: .keyPath)
        }
    }
}

// MARK: - SSH Test Result

struct SSHTestResult {
    let success: Bool
    let message: String
    let serverInfo: String?
    let latencyMs: UInt64?
}

// MARK: - SSH Key Info

struct SSHKeyInfo: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let type: SSHKeyType
    let hasPublicKey: Bool

    enum SSHKeyType: String {
        case rsa = "RSA"
        case ed25519 = "Ed25519"
        case ecdsa = "ECDSA"
        case dsa = "DSA"
        case unknown = "Unknown"
    }
}
