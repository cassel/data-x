import Foundation

@Observable
final class FilterViewModel {
    // MARK: - Filter State

    var selectedCategories: Set<FileCategory> = Set(FileCategory.allCases)
    var minSize: UInt64?
    var maxSize: UInt64?
    var minDate: Date?
    var maxDate: Date?
    var showHiddenFiles = false
    var showDirectoriesOnly = false
    var showFilesOnly = false

    // MARK: - Presets

    enum SizePreset: String, CaseIterable, Identifiable {
        case all = "All Sizes"
        case large = "> 100 MB"
        case veryLarge = "> 1 GB"
        case huge = "> 10 GB"

        var id: String { rawValue }

        var minSize: UInt64? {
            switch self {
            case .all: return nil
            case .large: return 100 * 1024 * 1024
            case .veryLarge: return 1024 * 1024 * 1024
            case .huge: return 10 * 1024 * 1024 * 1024
            }
        }
    }

    enum DatePreset: String, CaseIterable, Identifiable {
        case all = "Any Time"
        case lastWeek = "Last Week"
        case lastMonth = "Last Month"
        case lastYear = "Last Year"
        case older = "Older than 1 Year"

        var id: String { rawValue }

        var dateRange: (min: Date?, max: Date?) {
            let now = Date()
            let calendar = Calendar.current

            switch self {
            case .all:
                return (nil, nil)
            case .lastWeek:
                return (calendar.date(byAdding: .weekOfYear, value: -1, to: now), nil)
            case .lastMonth:
                return (calendar.date(byAdding: .month, value: -1, to: now), nil)
            case .lastYear:
                return (calendar.date(byAdding: .year, value: -1, to: now), nil)
            case .older:
                return (nil, calendar.date(byAdding: .year, value: -1, to: now))
            }
        }
    }

    var sizePreset: SizePreset = .all {
        didSet {
            minSize = sizePreset.minSize
            maxSize = nil
        }
    }

    var datePreset: DatePreset = .all {
        didSet {
            let range = datePreset.dateRange
            minDate = range.min
            maxDate = range.max
        }
    }

    // MARK: - Computed

    var isFiltering: Bool {
        selectedCategories.count < FileCategory.allCases.count ||
        minSize != nil ||
        maxSize != nil ||
        minDate != nil ||
        maxDate != nil ||
        showHiddenFiles ||
        showDirectoriesOnly ||
        showFilesOnly
    }

    var activeFilterCount: Int {
        var count = 0
        if selectedCategories.count < FileCategory.allCases.count { count += 1 }
        if minSize != nil || maxSize != nil { count += 1 }
        if minDate != nil || maxDate != nil { count += 1 }
        if showHiddenFiles { count += 1 }
        if showDirectoriesOnly || showFilesOnly { count += 1 }
        return count
    }

    // MARK: - Filtering

    func matches(_ node: FileNode) -> Bool {
        // Category filter
        if !node.isDirectory && !selectedCategories.contains(node.category) {
            return false
        }

        // Size filter
        if let minSize, node.size < minSize {
            return false
        }
        if let maxSize, node.size > maxSize {
            return false
        }

        // Date filter
        if let nodeDate = node.modificationDate {
            if let minDate, nodeDate < minDate {
                return false
            }
            if let maxDate, nodeDate > maxDate {
                return false
            }
        }

        // Hidden files
        if !showHiddenFiles && node.isHidden {
            return false
        }

        // Type filter
        if showDirectoriesOnly && !node.isDirectory {
            return false
        }
        if showFilesOnly && node.isDirectory {
            return false
        }

        return true
    }

    func filter(_ nodes: [FileNode]) -> [FileNode] {
        nodes.filter { matches($0) }
    }

    // MARK: - Actions

    func reset() {
        selectedCategories = Set(FileCategory.allCases)
        minSize = nil
        maxSize = nil
        minDate = nil
        maxDate = nil
        showHiddenFiles = false
        showDirectoriesOnly = false
        showFilesOnly = false
        sizePreset = .all
        datePreset = .all
    }

    func toggleCategory(_ category: FileCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
    }

    func selectAllCategories() {
        selectedCategories = Set(FileCategory.allCases)
    }

    func deselectAllCategories() {
        selectedCategories = []
    }
}
