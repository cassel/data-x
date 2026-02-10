import Foundation
import SwiftUI

@Observable
final class SSHViewModel {
    // MARK: - State

    var connections: [SSHConnection] = []
    var isExpanded = true
    var showConnectionModal = false
    var editingConnection: SSHConnection?
    var testingConnectionId: String?
    var testResult: SSHTestResult?
    var isConnecting = false
    var connectingId: String?
    var error: String?
    var detectedKeys: [SSHKeyInfo] = []

    // MARK: - Private

    private let sshService = SSHService()

    // MARK: - Init

    init() {
        loadConnections()
        detectSSHKeys()
    }

    // MARK: - Connection Management

    func loadConnections() {
        connections = SSHConnectionStore.loadAll()
    }

    func saveConnection(_ connection: SSHConnection, password: String?) {
        do {
            try SSHConnectionStore.save(connection)
            if let password, connection.authMethod == .password {
                SSHConnectionStore.storePassword(password, for: connection.id)
            }
            loadConnections()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteConnection(_ id: String) {
        do {
            try SSHConnectionStore.delete(id)
            loadConnections()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Test Connection

    func testConnection(_ connection: SSHConnection) {
        testingConnectionId = connection.id
        testResult = nil

        Task {
            let result = await sshService.testConnection(connection)
            await MainActor.run {
                self.testResult = result
                self.testingConnectionId = nil
            }
        }
    }

    // MARK: - Remote Scan

    func connect(
        _ connection: SSHConnection,
        path: String? = nil,
        scannerVM: ScannerViewModel
    ) {
        isConnecting = true
        connectingId = connection.id
        error = nil
        scannerVM.isScanning = true
        scannerVM.progress = .initial

        sshService.scanRemote(
            connection: connection,
            path: path,
            progress: { progress in
                scannerVM.progress = progress
            },
            completion: { [weak self] result in
                self?.isConnecting = false
                self?.connectingId = nil

                switch result {
                case .success(let root):
                    scannerVM.rootNode = root
                    scannerVM.currentNode = root
                    scannerVM.navigationStack = [root]
                    scannerVM.isScanning = false
                case .failure(let err):
                    scannerVM.error = err
                    scannerVM.isScanning = false
                    self?.error = err.localizedDescription
                }
            }
        )
    }

    func cancelConnection() {
        sshService.cancel()
        isConnecting = false
        connectingId = nil
    }

    // MARK: - SSH Key Detection

    func detectSSHKeys() {
        detectedKeys = SSHKeyManager.detectKeys()
    }

    // MARK: - Helpers

    func addNewConnection() {
        editingConnection = nil
        showConnectionModal = true
    }

    func editConnection(_ connection: SSHConnection) {
        editingConnection = connection
        showConnectionModal = true
    }
}
