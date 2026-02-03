import Foundation

struct ScanProgress: Sendable {
    let filesScanned: Int
    let directoriesScanned: Int
    let bytesScanned: UInt64
    let currentPath: String
    let startTime: Date
    let isComplete: Bool

    var formattedBytes: String {
        SizeFormatter.format(bytesScanned)
    }

    var elapsedTime: TimeInterval {
        Date().timeIntervalSince(startTime)
    }

    var formattedElapsedTime: String {
        let seconds = Int(elapsedTime)
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            return "\(seconds / 60)m \(seconds % 60)s"
        } else {
            return "\(seconds / 3600)h \(seconds % 3600 / 60)m"
        }
    }

    var filesPerSecond: Double {
        guard elapsedTime > 0 else { return 0 }
        return Double(filesScanned) / elapsedTime
    }

    static let initial = ScanProgress(
        filesScanned: 0,
        directoriesScanned: 0,
        bytesScanned: 0,
        currentPath: "",
        startTime: Date(),
        isComplete: false
    )

    func with(
        filesScanned: Int? = nil,
        directoriesScanned: Int? = nil,
        bytesScanned: UInt64? = nil,
        currentPath: String? = nil,
        isComplete: Bool? = nil
    ) -> ScanProgress {
        ScanProgress(
            filesScanned: filesScanned ?? self.filesScanned,
            directoriesScanned: directoriesScanned ?? self.directoriesScanned,
            bytesScanned: bytesScanned ?? self.bytesScanned,
            currentPath: currentPath ?? self.currentPath,
            startTime: self.startTime,
            isComplete: isComplete ?? self.isComplete
        )
    }
}
