import Foundation

enum ScanEvent: Sendable {
    case progress(ScanProgress)
    case partialTree(FileNodeData)
    case complete(FileNodeData)
    case databaseComplete
}
