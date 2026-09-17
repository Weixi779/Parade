// Created by weixi on 2026/09/17.

extension Sequence {
    /// Builds a lookup, resolving each collision with its key, current value,
    /// and incoming element. The resolved value remains under that key.
    ///
    /// Consumes the sequence once, projecting each element once. Dictionary
    /// order is unspecified; throwing stops consumption without rolling it back.
    func indexed<Key: Hashable, Failure: Error>(
        by key: (Element) -> Key,
        uniquingWith resolve: (Key, Element, Element) throws(Failure) -> Element
    ) throws(Failure) -> [Key: Element] {
        var index = IndexBuilder<Key, Element>(minimumCapacity: underestimatedCount)
        for element in self {
            try index.insert(element, forKey: key(element), uniquingWith: resolve)
        }
        return index.values
    }

    /// Rejects the first duplicate with the caller's error, preserving both
    /// occurrences and the concrete error type at the call site.
    func indexedByUniqueKey<Key: Hashable, Failure: Error>(
        _ key: (Element) -> Key,
        duplicate: (Key, Element, Element) -> Failure
    ) throws(Failure) -> [Key: Element] {
        try indexed(by: key) { (key, first, incoming) throws(Failure) in
            throw duplicate(key, first, incoming)
        }
    }
}

/// Shares collision handling with callers that must interleave several indexes.
struct IndexBuilder<Key: Hashable, Value> {
    private(set) var values: [Key: Value]

    init(minimumCapacity: Int = 0) {
        values = Dictionary(minimumCapacity: minimumCapacity)
    }

    mutating func insert<Failure: Error>(
        _ value: Value,
        forKey key: Key,
        uniquingWith resolve: (Key, Value, Value) throws(Failure) -> Value
    ) throws(Failure) {
        if let current = values[key] {
            let resolved = try resolve(key, current, value)
            values.updateValue(resolved, forKey: key)
        } else {
            values.updateValue(value, forKey: key)
        }
    }

    mutating func insert<Failure: Error>(
        _ value: Value,
        forKey key: Key,
        duplicate: (Key, Value, Value) -> Failure
    ) throws(Failure) {
        try insert(value, forKey: key) { (key, first, incoming) throws(Failure) in
            throw duplicate(key, first, incoming)
        }
    }
}
