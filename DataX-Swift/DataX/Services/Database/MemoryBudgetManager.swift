import Foundation

/// Computes the optimal in-memory node budget based on physical RAM.
///
/// The LRU cache in ``VirtualTreeProvider`` already handles eviction automatically.
/// This manager's role is to **calculate** the right capacity value and allow user overrides
/// via `@AppStorage("nodeBudgetOverride")`.
///
/// - Budget formula: `min(max(Int(physicalMemory × 0.10 / 600), 10_000), 500_000)`
/// - 10% of RAM ÷ ~600 bytes per FileNode, clamped to [10k, 500k]
enum MemoryBudgetManager {

    /// Calculates the node budget based on physical RAM.
    ///
    /// | Mac RAM | Nodes  |
    /// |---------|--------|
    /// | 8 GB    | 14,000 |
    /// | 32 GB   | 55,000 |
    /// | 64 GB   | 110,000|
    static func defaultBudget() -> Int {
        let physicalMemory = Double(ProcessInfo.processInfo.physicalMemory)
        let raw = Int(physicalMemory * 0.10 / 600.0)
        return min(max(raw, 10_000), 500_000)
    }

    /// Returns the user-overridden budget if set, otherwise ``defaultBudget()``.
    ///
    /// An override value of `0` (or absent) means "use system default".
    static func effectiveBudget() -> Int {
        let override = UserDefaults.standard.integer(forKey: "nodeBudgetOverride")
        guard override > 0 else { return defaultBudget() }
        return min(override, 500_000)
    }
}
