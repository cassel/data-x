import SwiftUI

struct FileTypeLegendOverlay: View {
    let node: FileNode

    private var stats: [FileTypeLegendStat] {
        FileTypeLegendStats.make(for: node)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("File Types", systemImage: "list.bullet.rectangle.portrait")
                    .font(.headline)

                Spacer()

                Text(node.formattedSize)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }

            if stats.isEmpty {
                Text("No categorized files in this folder")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(stats) { stat in
                        FileTypeLegendRow(stat: stat, totalSize: node.size)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
    }
}

struct FileTypeLegendStat: Identifiable, Equatable {
    let category: FileCategory
    let size: UInt64
    let count: Int

    var id: FileCategory { category }

    func percentage(of totalSize: UInt64) -> Double {
        guard totalSize > 0 else { return 0 }
        return Double(size) / Double(totalSize)
    }
}

enum FileTypeLegendStats {
    static func make(for node: FileNode) -> [FileTypeLegendStat] {
        var categorySizes: [FileCategory: UInt64] = [:]
        var categoryCounts: [FileCategory: Int] = [:]

        func traverse(_ current: FileNode) {
            if current.isDirectory {
                current.children?.forEach(traverse)
            } else {
                let category = current.category
                categorySizes[category, default: 0] += current.size
                categoryCounts[category, default: 0] += 1
            }
        }

        traverse(node)

        return FileCategory.allCases.compactMap { category in
            let size = categorySizes[category] ?? 0
            guard size > 0 else { return nil }

            return FileTypeLegendStat(
                category: category,
                size: size,
                count: categoryCounts[category] ?? 0
            )
        }
        .sorted { lhs, rhs in
            if lhs.size != rhs.size {
                return lhs.size > rhs.size
            }

            return lhs.category.displayName.localizedCaseInsensitiveCompare(rhs.category.displayName) == .orderedAscending
        }
    }
}

private struct FileTypeLegendRow: View {
    let stat: FileTypeLegendStat
    let totalSize: UInt64

    private var percentage: Double {
        stat.percentage(of: totalSize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(stat.category.color)
                    .frame(width: 9, height: 9)

                Text(stat.category.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                Text(SizeFormatter.format(stat.size))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            HStack {
                Text(percentage, format: .percent.precision(.fractionLength(0)))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(stat.count) \(stat.count == 1 ? "file" : "files")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))

                    Capsule()
                        .fill(stat.category.color)
                        .frame(width: geometry.size.width * percentage)
                }
            }
            .frame(height: 4)
        }
    }
}
