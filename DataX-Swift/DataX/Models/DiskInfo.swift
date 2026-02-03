import Foundation

struct DiskInfo: Sendable {
    let totalSpace: UInt64
    let usedSpace: UInt64
    let freeSpace: UInt64
    let volumeName: String
    let volumePath: URL

    var usedPercentage: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(usedSpace) / Double(totalSpace) * 100
    }

    var freePercentage: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(freeSpace) / Double(totalSpace) * 100
    }

    var formattedTotal: String {
        SizeFormatter.format(totalSpace)
    }

    var formattedUsed: String {
        SizeFormatter.format(usedSpace)
    }

    var formattedFree: String {
        SizeFormatter.format(freeSpace)
    }

    static func forPath(_ url: URL) throws -> DiskInfo {
        let values = try url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeNameKey
        ])

        let total = UInt64(values.volumeTotalCapacity ?? 0)
        let availableForImportant = values.volumeAvailableCapacityForImportantUsage
        let availableBasic = values.volumeAvailableCapacity ?? 0
        let available = UInt64(availableForImportant ?? Int64(availableBasic))

        return DiskInfo(
            totalSpace: total,
            usedSpace: total - available,
            freeSpace: available,
            volumeName: values.volumeName ?? "Unknown Volume",
            volumePath: url
        )
    }
}
