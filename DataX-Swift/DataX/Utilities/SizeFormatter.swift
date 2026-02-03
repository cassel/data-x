import Foundation

enum SizeFormatter {
    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    static func format(_ bytes: UInt64) -> String {
        byteCountFormatter.string(fromByteCount: Int64(bytes))
    }

    static func format(_ bytes: Int64) -> String {
        byteCountFormatter.string(fromByteCount: bytes)
    }

    static func formatCompact(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        formatter.zeroPadsFractionDigits = false
        return formatter.string(fromByteCount: Int64(bytes))
    }

    static func parseSize(_ string: String) -> UInt64? {
        let normalized = string.uppercased().trimmingCharacters(in: .whitespaces)

        let patterns: [(String, UInt64)] = [
            ("TB", 1024 * 1024 * 1024 * 1024),
            ("GB", 1024 * 1024 * 1024),
            ("MB", 1024 * 1024),
            ("KB", 1024),
            ("B", 1)
        ]

        for (suffix, multiplier) in patterns {
            if normalized.hasSuffix(suffix) {
                let numberPart = normalized.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)
                if let value = Double(numberPart) {
                    return UInt64(value * Double(multiplier))
                }
            }
        }

        return UInt64(normalized)
    }
}
