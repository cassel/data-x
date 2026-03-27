import Testing
import Foundation
@testable import DataX

@Suite("MemoryBudgetManager Tests")
struct MemoryBudgetManagerTests {

    // MARK: - defaultBudget()

    @Test("defaultBudget returns value within valid range [10_000, 500_000]")
    func testDefaultBudgetRange() {
        let budget = MemoryBudgetManager.defaultBudget()
        #expect(budget >= 10_000)
        #expect(budget <= 500_000)
    }

    @Test("defaultBudget is proportional to physical memory (> 10_000 on modern Mac)")
    func testDefaultBudgetProportional() {
        let budget = MemoryBudgetManager.defaultBudget()
        // Any modern Mac has at least 8GB, so budget should be > 10_000
        #expect(budget > 10_000)
    }

    @Test("defaultBudget matches expected formula")
    func testDefaultBudgetFormula() {
        let physicalMemory = Double(ProcessInfo.processInfo.physicalMemory)
        let expected = min(max(Int(physicalMemory * 0.10 / 600.0), 10_000), 500_000)
        #expect(MemoryBudgetManager.defaultBudget() == expected)
    }

    // MARK: - effectiveBudget() with override

    @Test("effectiveBudget returns override when set to positive value")
    func testOverridePositive() {
        let previousValue = UserDefaults.standard.integer(forKey: "nodeBudgetOverride")
        defer { UserDefaults.standard.set(previousValue, forKey: "nodeBudgetOverride") }

        UserDefaults.standard.set(25_000, forKey: "nodeBudgetOverride")
        #expect(MemoryBudgetManager.effectiveBudget() == 25_000)
    }

    @Test("effectiveBudget falls back to defaultBudget when override is 0")
    func testOverrideZeroFallback() {
        let previousValue = UserDefaults.standard.integer(forKey: "nodeBudgetOverride")
        defer { UserDefaults.standard.set(previousValue, forKey: "nodeBudgetOverride") }

        UserDefaults.standard.set(0, forKey: "nodeBudgetOverride")
        #expect(MemoryBudgetManager.effectiveBudget() == MemoryBudgetManager.defaultBudget())
    }

    @Test("effectiveBudget falls back to defaultBudget when override is absent")
    func testOverrideAbsentFallback() {
        let previousValue = UserDefaults.standard.integer(forKey: "nodeBudgetOverride")
        defer { UserDefaults.standard.set(previousValue, forKey: "nodeBudgetOverride") }

        UserDefaults.standard.removeObject(forKey: "nodeBudgetOverride")
        #expect(MemoryBudgetManager.effectiveBudget() == MemoryBudgetManager.defaultBudget())
    }
}
