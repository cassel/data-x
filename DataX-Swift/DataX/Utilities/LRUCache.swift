import Foundation

/// A generic Least-Recently-Used cache with O(1) access, insertion, and eviction.
/// Uses a doubly-linked list + Dictionary internally.
///
/// **Thread Safety:** NOT independently thread-safe. All access must be serialized
/// externally (e.g., by VirtualTreeProvider's serial DispatchQueue).
final class LRUCache<Key: Hashable, Value>: @unchecked Sendable {
    private final class Node {
        let key: Key
        var value: Value
        var prev: Node?
        var next: Node?

        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }

    let capacity: Int
    var count: Int { dict.count }
    var onEvict: ((Key, Value) -> Void)?

    private var dict: [Key: Node] = [:]
    private var head: Node? // Most recently used
    private var tail: Node? // Least recently used

    init(capacity: Int) {
        precondition(capacity > 0, "LRUCache capacity must be positive")
        self.capacity = capacity
    }

    func get(_ key: Key) -> Value? {
        guard let node = dict[key] else { return nil }
        moveToHead(node)
        return node.value
    }

    func set(_ key: Key, value: Value) {
        if let existing = dict[key] {
            existing.value = value
            moveToHead(existing)
        } else {
            let node = Node(key: key, value: value)
            dict[key] = node
            addToHead(node)
            if dict.count > capacity {
                evictTail()
            }
        }
    }

    func remove(_ key: Key) {
        guard let node = dict.removeValue(forKey: key) else { return }
        detach(node)
    }

    func removeAll() {
        dict.removeAll()
        head = nil
        tail = nil
    }

    // MARK: - Linked List Operations

    private func addToHead(_ node: Node) {
        node.prev = nil
        node.next = head
        head?.prev = node
        head = node
        if tail == nil {
            tail = node
        }
    }

    private func detach(_ node: Node) {
        let prev = node.prev
        let next = node.next

        prev?.next = next
        next?.prev = prev

        if head === node { head = next }
        if tail === node { tail = prev }

        node.prev = nil
        node.next = nil
    }

    private func moveToHead(_ node: Node) {
        guard head !== node else { return }
        detach(node)
        addToHead(node)
    }

    private func evictTail() {
        guard let tailNode = tail else { return }
        dict.removeValue(forKey: tailNode.key)
        detach(tailNode)
        onEvict?(tailNode.key, tailNode.value)
    }
}
