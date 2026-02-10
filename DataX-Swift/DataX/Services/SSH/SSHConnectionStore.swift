import Foundation
import Security

/// Persists SSH connections to ~/.config/data-x/ssh_connections.json
/// Compatible with the Tauri version's storage format
enum SSHConnectionStore {
    private static let configDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appending(path: ".config/data-x")
    }()

    private static var connectionsFile: URL {
        configDir.appending(path: "ssh_connections.json")
    }

    private static let keychainService = "data-x-ssh"

    // MARK: - Connection CRUD

    static func loadAll() -> [SSHConnection] {
        let fm = FileManager.default

        guard fm.fileExists(atPath: connectionsFile.path),
              let data = try? Data(contentsOf: connectionsFile),
              let connections = try? JSONDecoder().decode([SSHConnection].self, from: data) else {
            return []
        }

        return connections
    }

    static func save(_ connection: SSHConnection) throws {
        var connections = loadAll()

        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }

        try persist(connections)
    }

    static func delete(_ id: String) throws {
        var connections = loadAll()
        connections.removeAll { $0.id == id }
        try persist(connections)
        deletePassword(for: id)
    }

    static func markUsed(_ id: String) throws {
        var connections = loadAll()
        if let index = connections.firstIndex(where: { $0.id == id }) {
            connections[index].lastUsedAt = Int64(Date().timeIntervalSince1970)
            try persist(connections)
        }
    }

    // MARK: - Persistence

    private static func persist(_ connections: [SSHConnection]) throws {
        let fm = FileManager.default

        if !fm.fileExists(atPath: configDir.path) {
            try fm.createDirectory(at: configDir, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(connections)
        try data.write(to: connectionsFile, options: .atomic)
    }

    // MARK: - Keychain (Password Storage)

    static func storePassword(_ password: String, for connectionId: String) {
        guard let data = password.data(using: .utf8) else { return }

        // Delete existing entry first
        deletePassword(for: connectionId)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: connectionId,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    static func getPassword(for connectionId: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: connectionId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }

        return password
    }

    static func deletePassword(for connectionId: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: connectionId
        ]

        SecItemDelete(query as CFDictionary)
    }
}
