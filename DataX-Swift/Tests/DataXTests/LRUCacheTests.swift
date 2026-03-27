import Testing
import Foundation
@testable import DataX

@Suite("LRUCache Tests")
struct LRUCacheTests {

    // MARK: - Basic Operations

    @Test("Get returns nil for missing key")
    func testGetMissingKey() {
        let cache = LRUCache<String, Int>(capacity: 5)
        #expect(cache.get("missing") == nil)
    }

    @Test("Set and get returns stored value")
    func testSetAndGet() {
        let cache = LRUCache<String, Int>(capacity: 5)
        cache.set("a", value: 1)
        #expect(cache.get("a") == 1)
        #expect(cache.count == 1)
    }

    @Test("Set overwrites existing value")
    func testSetOverwrite() {
        let cache = LRUCache<String, Int>(capacity: 5)
        cache.set("a", value: 1)
        cache.set("a", value: 2)
        #expect(cache.get("a") == 2)
        #expect(cache.count == 1)
    }

    // MARK: - LRU Eviction

    @Test("Evicts oldest when exceeding capacity")
    func testEvictionOldest() {
        let cache = LRUCache<String, Int>(capacity: 3)
        cache.set("a", value: 1)
        cache.set("b", value: 2)
        cache.set("c", value: 3)

        // Adding 4th item should evict "a" (oldest)
        cache.set("d", value: 4)

        #expect(cache.get("a") == nil)
        #expect(cache.get("b") == 2)
        #expect(cache.get("c") == 3)
        #expect(cache.get("d") == 4)
        #expect(cache.count == 3)
    }

    @Test("Access promotes item, second-oldest evicted instead")
    func testPromotionOnAccess() {
        let cache = LRUCache<String, Int>(capacity: 3)
        cache.set("a", value: 1)
        cache.set("b", value: 2)
        cache.set("c", value: 3)

        // Access "a" — promotes it to MRU
        _ = cache.get("a")

        // Adding "d" should evict "b" (now LRU), not "a"
        cache.set("d", value: 4)

        #expect(cache.get("a") == 1)
        #expect(cache.get("b") == nil)
        #expect(cache.get("c") == 3)
        #expect(cache.get("d") == 4)
    }

    // MARK: - onEvict Callback

    @Test("onEvict callback fires with correct key and value")
    func testOnEvictCallback() {
        let cache = LRUCache<String, Int>(capacity: 2)
        var evictedPairs: [(String, Int)] = []
        cache.onEvict = { key, value in
            evictedPairs.append((key, value))
        }

        cache.set("a", value: 10)
        cache.set("b", value: 20)
        cache.set("c", value: 30) // evicts "a"

        #expect(evictedPairs.count == 1)
        #expect(evictedPairs[0].0 == "a")
        #expect(evictedPairs[0].1 == 10)
    }

    @Test("onEvict fires for each eviction")
    func testOnEvictMultiple() {
        let cache = LRUCache<String, Int>(capacity: 1)
        var evictedKeys: [String] = []
        cache.onEvict = { key, _ in evictedKeys.append(key) }

        cache.set("a", value: 1)
        cache.set("b", value: 2) // evicts a
        cache.set("c", value: 3) // evicts b

        #expect(evictedKeys == ["a", "b"])
    }

    // MARK: - Remove

    @Test("Remove single key")
    func testRemove() {
        let cache = LRUCache<String, Int>(capacity: 5)
        cache.set("a", value: 1)
        cache.set("b", value: 2)

        cache.remove("a")

        #expect(cache.get("a") == nil)
        #expect(cache.get("b") == 2)
        #expect(cache.count == 1)
    }

    @Test("Remove non-existent key is no-op")
    func testRemoveNonExistent() {
        let cache = LRUCache<String, Int>(capacity: 5)
        cache.set("a", value: 1)
        cache.remove("z")
        #expect(cache.count == 1)
    }

    // MARK: - RemoveAll

    @Test("RemoveAll clears entire cache")
    func testRemoveAll() {
        let cache = LRUCache<String, Int>(capacity: 5)
        cache.set("a", value: 1)
        cache.set("b", value: 2)
        cache.set("c", value: 3)

        cache.removeAll()

        #expect(cache.count == 0)
        #expect(cache.get("a") == nil)
        #expect(cache.get("b") == nil)
        #expect(cache.get("c") == nil)
    }

    // MARK: - Capacity Property

    @Test("Capacity property matches init value")
    func testCapacity() {
        let cache = LRUCache<Int, String>(capacity: 42)
        #expect(cache.capacity == 42)
    }

    // MARK: - Edge Cases

    @Test("Capacity of 1 works correctly")
    func testCapacityOne() {
        let cache = LRUCache<String, Int>(capacity: 1)
        cache.set("a", value: 1)
        #expect(cache.get("a") == 1)

        cache.set("b", value: 2)
        #expect(cache.get("a") == nil)
        #expect(cache.get("b") == 2)
        #expect(cache.count == 1)
    }

    @Test("Remove head and tail nodes correctly")
    func testRemoveHeadAndTail() {
        let cache = LRUCache<String, Int>(capacity: 3)
        cache.set("a", value: 1) // tail
        cache.set("b", value: 2)
        cache.set("c", value: 3) // head

        // Remove head
        cache.remove("c")
        #expect(cache.count == 2)

        // Remove tail
        cache.remove("a")
        #expect(cache.count == 1)
        #expect(cache.get("b") == 2)
    }
}
