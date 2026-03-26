import Foundation

/// Detects and manages SSH keys on the local system
enum SSHKeyManager {
    private static let sshDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".ssh")
    }()

    private static let knownKeyFiles = [
        "id_ed25519", "id_rsa", "id_ecdsa", "id_dsa"
    ]

    // MARK: - Key Detection

    /// Discover all SSH keys in ~/.ssh/
    static func detectKeys() -> [SSHKeyInfo] {
        let fm = FileManager.default

        guard fm.fileExists(atPath: sshDirectory.path) else {
            return []
        }

        var keys: [SSHKeyInfo] = []

        for keyFile in knownKeyFiles {
            let privatePath = sshDirectory.appending(path: keyFile)
            let publicPath = sshDirectory.appending(path: "\(keyFile).pub")

            if fm.fileExists(atPath: privatePath.path) {
                let keyType: SSHKeyInfo.SSHKeyType = switch keyFile {
                case "id_ed25519": .ed25519
                case "id_rsa": .rsa
                case "id_ecdsa": .ecdsa
                case "id_dsa": .dsa
                default: .unknown
                }

                keys.append(SSHKeyInfo(
                    name: keyFile,
                    path: privatePath.path,
                    type: keyType,
                    hasPublicKey: fm.fileExists(atPath: publicPath.path)
                ))
            }
        }

        // Also scan for custom key files (non-standard names)
        if let contents = try? fm.contentsOfDirectory(atPath: sshDirectory.path) {
            for file in contents {
                // Skip known files, public keys, config files, and known_hosts
                if knownKeyFiles.contains(file) { continue }
                if file.hasSuffix(".pub") { continue }
                if ["config", "known_hosts", "known_hosts.old", "authorized_keys", "environment"].contains(file) { continue }
                if file.hasPrefix(".") { continue }

                let filePath = sshDirectory.appending(path: file)
                // Check if it looks like a private key (starts with -----)
                if let content = try? String(contentsOf: filePath, encoding: .utf8),
                   content.hasPrefix("-----BEGIN") {
                    let hasPublic = fm.fileExists(atPath: "\(filePath.path).pub")
                    keys.append(SSHKeyInfo(
                        name: file,
                        path: filePath.path,
                        type: .unknown,
                        hasPublicKey: hasPublic
                    ))
                }
            }
        }

        return keys
    }

    /// Check if the user has any SSH keys
    static var hasKeys: Bool {
        !detectKeys().isEmpty
    }

    /// Get the default key path (first available)
    static var defaultKeyPath: String? {
        detectKeys().first?.path
    }

    /// Check if a host is in known_hosts
    static func isKnownHost(_ host: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = ["-F", host]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            return false
        }
    }
}
