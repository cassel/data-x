import Foundation

/// Executes SSH operations using the system's ssh binary
final class SSHService {
    private var currentProcess: Process?

    // MARK: - Connection Test

    func testConnection(_ connection: SSHConnection) async -> SSHTestResult {
        let args = buildSSHArgs(for: connection)
        let start = Date()

        let (useSSHPass, password) = resolveAuth(for: connection)

        var process = Process()
        if useSSHPass {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["sshpass", "-p", password ?? ""] + ["ssh"] + args + ["echo 'Data-X connection test' && uname -a"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = args + ["echo 'Data-X connection test' && uname -a"]
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()

            let latency = UInt64(Date().timeIntervalSince(start) * 1000)

            if process.terminationStatus == 0 {
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let lines = output.split(separator: "\n")
                let serverInfo = lines.count > 1 ? String(lines[1]) : nil

                return SSHTestResult(
                    success: true,
                    message: "Connection successful",
                    serverInfo: serverInfo,
                    latencyMs: latency
                )
            } else {
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"

                return SSHTestResult(
                    success: false,
                    message: "Connection failed: \(errMsg)",
                    serverInfo: nil,
                    latencyMs: nil
                )
            }
        } catch {
            return SSHTestResult(
                success: false,
                message: "Failed to execute SSH: \(error.localizedDescription)",
                serverInfo: nil,
                latencyMs: nil
            )
        }
    }

    // MARK: - Remote Scan

    func scanRemote(
        connection: SSHConnection,
        path: String?,
        progress: @escaping (ScanProgress) -> Void,
        completion: @escaping (Result<FileNode, Error>) -> Void
    ) {
        let scanPath = path ?? connection.defaultPath ?? "/"
        let args = buildSSHArgs(for: connection)
        let (useSSHPass, password) = resolveAuth(for: connection)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let startTime = Date()

            // Emit initial progress
            DispatchQueue.main.async {
                progress(ScanProgress(
                    filesScanned: 0,
                    directoriesScanned: 0,
                    bytesScanned: 0,
                    currentPath: "Connecting to \(connection.host)...",
                    startTime: startTime,
                    isComplete: false
                ))
            }

            // First check if data-x CLI is available on remote
            let hasDataX = self?.checkRemoteDataX(args: args, useSSHPass: useSSHPass, password: password) ?? false

            let result: Result<FileNode, Error>

            if hasDataX {
                result = self?.scanWithDataX(args: args, path: scanPath, useSSHPass: useSSHPass, password: password, startTime: startTime, progress: progress) ?? .failure(SSHError.cancelled)
            } else {
                result = self?.scanWithFind(args: args, path: scanPath, useSSHPass: useSSHPass, password: password, startTime: startTime, progress: progress) ?? .failure(SSHError.cancelled)
            }

            // Mark connection as used
            if case .success = result {
                try? SSHConnectionStore.markUsed(connection.id)
            }

            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func cancel() {
        currentProcess?.terminate()
        currentProcess = nil
    }

    // MARK: - Private - SSH Args

    private func buildSSHArgs(for connection: SSHConnection) -> [String] {
        var args: [String] = []

        // Disable pseudo-terminal
        args.append("-T")

        // Host key checking
        args.append(contentsOf: ["-o", "StrictHostKeyChecking=accept-new"])

        // Timeout
        args.append(contentsOf: ["-o", "ConnectTimeout=\(connection.timeoutSecs)"])

        // Keep-alive
        args.append(contentsOf: ["-o", "ServerAliveInterval=5"])
        args.append(contentsOf: ["-o", "ServerAliveCountMax=3"])

        // Batch mode for non-password auth
        if connection.authMethod != .password {
            args.append(contentsOf: ["-o", "BatchMode=yes"])
            args.append(contentsOf: ["-o", "PasswordAuthentication=no"])
        }

        // Port
        if connection.port != 22 {
            args.append(contentsOf: ["-p", "\(connection.port)"])
        }

        // Key file
        if connection.authMethod == .key, let keyPath = connection.keyPath {
            args.append(contentsOf: ["-i", keyPath])
        }

        // user@host
        args.append("\(connection.username)@\(connection.host)")

        return args
    }

    private func resolveAuth(for connection: SSHConnection) -> (useSSHPass: Bool, password: String?) {
        if connection.authMethod == .password {
            let password = SSHConnectionStore.getPassword(for: connection.id)
            return (true, password)
        }
        return (false, nil)
    }

    private func makeProcess(args: [String], command: String, useSSHPass: Bool, password: String?) -> Process {
        let process = Process()

        if useSSHPass {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["sshpass", "-p", password ?? ""] + ["ssh"] + args + [command]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = args + [command]
        }

        return process
    }

    // MARK: - Private - Remote data-x check

    private func checkRemoteDataX(args: [String], useSSHPass: Bool, password: String?) -> Bool {
        let process = makeProcess(args: args, command: "which data-x 2>/dev/null || echo ''", useSSHPass: useSSHPass, password: password)
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

    // MARK: - Private - Scan with data-x CLI

    private func scanWithDataX(
        args: [String],
        path: String,
        useSSHPass: Bool,
        password: String?,
        startTime: Date,
        progress: @escaping (ScanProgress) -> Void
    ) -> Result<FileNode, Error> {
        let process = makeProcess(args: args, command: "data-x --json '\(path)'", useSSHPass: useSSHPass, password: password)
        currentProcess = process

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            currentProcess = nil

            guard process.terminationStatus == 0 else {
                return .failure(SSHError.scanFailed("Remote data-x scan failed"))
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let json = String(data: data, encoding: .utf8) ?? ""

            // Parse the JSON from data-x CLI into our FileNode tree
            let remoteRoot = try parseDataXJSON(json, path: path)
            return .success(remoteRoot)
        } catch {
            currentProcess = nil
            return .failure(error)
        }
    }

    // MARK: - Private - Scan with find (fallback)

    private func scanWithFind(
        args: [String],
        path: String,
        useSSHPass: Bool,
        password: String?,
        startTime: Date,
        progress: @escaping (ScanProgress) -> Void
    ) -> Result<FileNode, Error> {
        let maxDepth = 4
        let findCmd = """
        if find '\(path)' -maxdepth 0 -printf '' 2>/dev/null; then \
        find '\(path)' -maxdepth \(maxDepth) -printf '%p|%y|%s\\n' 2>/dev/null; \
        else \
        find '\(path)' -maxdepth \(maxDepth) -exec sh -c 'for f; do \
        if [ -d "$f" ]; then t=d; else t=f; fi; \
        s=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0); \
        printf "%s|%s|%s\\n" "$f" "$t" "$s"; \
        done' _ {} +; \
        fi
        """

        let process = makeProcess(args: args, command: findCmd, useSSHPass: useSSHPass, password: password)
        currentProcess = process

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            currentProcess = nil

            guard process.terminationStatus == 0 || !data.isEmpty else {
                return .failure(SSHError.scanFailed("Remote scan failed"))
            }

            let output = String(data: data, encoding: .utf8) ?? ""
            let lines = output.split(separator: "\n")

            var files: [(path: String, isDir: Bool, size: UInt64)] = []
            var filesFound = 0

            for line in lines {
                let parts = line.split(separator: "|", maxSplits: 2)
                guard parts.count >= 3 else { continue }

                let filePath = String(parts[0])
                let fileType = String(parts[1])
                let size = UInt64(parts[2]) ?? 0
                let isDir = fileType == "d" || fileType == "Directory"

                files.append((filePath, isDir, size))
                filesFound += 1

                if filesFound % 100 == 0 {
                    let p = ScanProgress(
                        filesScanned: filesFound,
                        directoriesScanned: 0,
                        bytesScanned: files.reduce(0) { $0 + $1.size },
                        currentPath: filePath,
                        startTime: startTime,
                        isComplete: false
                    )
                    DispatchQueue.main.async { progress(p) }
                }
            }

            guard !files.isEmpty else {
                return .failure(SSHError.scanFailed("No files found at '\(path)'. Check that the path exists and you have permission."))
            }

            let root = buildTree(from: files, rootPath: path)
            return .success(root)
        } catch {
            currentProcess = nil
            return .failure(error)
        }
    }

    // MARK: - Private - Tree Building

    private func parseDataXJSON(_ json: String, path: String) throws -> FileNode {
        // data-x CLI outputs JSON with: id, name, path, size, is_dir, is_hidden, extension, children, file_count
        struct RemoteNode: Decodable {
            let name: String
            let path: String
            let size: UInt64
            let is_dir: Bool
            let is_hidden: Bool?
            let `extension`: String?
            let children: [RemoteNode]?
            let file_count: UInt64?
        }

        guard let data = json.data(using: .utf8) else {
            throw SSHError.scanFailed("Invalid JSON response")
        }

        let remote = try JSONDecoder().decode(RemoteNode.self, from: data)

        func convert(_ remote: RemoteNode) -> FileNode {
            let url = URL(fileURLWithPath: remote.path)
            let node = FileNode(
                url: url,
                isDirectory: remote.is_dir,
                size: remote.size
            )
            if let children = remote.children {
                node.children = children.map { convert($0) }
                node.size = node.children?.reduce(0) { $0 + $1.size } ?? 0
                node.fileCount = node.children?.reduce(0) { $0 + $1.fileCount } ?? 0
            }
            return node
        }

        return convert(remote)
    }

    private func buildTree(from files: [(path: String, isDir: Bool, size: UInt64)], rootPath: String) -> FileNode {
        // Build a flat list and then assemble the tree
        let rootURL = URL(fileURLWithPath: rootPath)
        let root = FileNode(url: rootURL, isDirectory: true)

        // Create nodes indexed by path
        var nodeMap: [String: FileNode] = [rootPath: root]

        // Sort by path depth (shallower first) to create parents before children
        let sorted = files.sorted { $0.path.components(separatedBy: "/").count < $1.path.components(separatedBy: "/").count }

        for file in sorted {
            if file.path == rootPath { continue }

            let url = URL(fileURLWithPath: file.path)
            let node = FileNode(url: url, isDirectory: file.isDir, size: file.size)
            if !file.isDir {
                node.fileCount = 1
            }
            nodeMap[file.path] = node

            // Find parent
            let parentPath = (file.path as NSString).deletingLastPathComponent
            if let parent = nodeMap[parentPath] {
                if parent.children == nil {
                    parent.children = []
                }
                parent.children?.append(node)
            }
        }

        // Calculate directory sizes bottom-up
        calculateSizes(root)

        // Sort children by size
        sortChildren(root)

        return root
    }

    private func calculateSizes(_ node: FileNode) {
        guard node.isDirectory, let children = node.children else { return }
        for child in children {
            calculateSizes(child)
        }
        node.size = children.reduce(0) { $0 + $1.size }
        node.fileCount = children.reduce(0) { $0 + $1.fileCount }
    }

    private func sortChildren(_ node: FileNode) {
        guard node.isDirectory, let children = node.children else { return }
        node.children = children.sorted { $0.size > $1.size }
        for child in children {
            sortChildren(child)
        }
    }
}

// MARK: - Errors

enum SSHError: LocalizedError {
    case scanFailed(String)
    case connectionFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .scanFailed(let msg): return msg
        case .connectionFailed(let msg): return msg
        case .cancelled: return "Operation cancelled"
        }
    }
}
