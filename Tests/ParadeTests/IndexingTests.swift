// Created by weixi on 2026/09/17.

import Testing
@testable import Parade

struct IndexingTests {
    @Test("Unique indexing preserves values and concrete error types", arguments: [0, 3])
    func uniqueValues(count: Int) throws {
        let items = (0..<count).map { Entry(id: $0, value: $0 * 10) }
        let index = try strictIndex(items)
        #expect(index.count == count)
        for item in items {
            #expect(index[item.id] == item)
        }
    }

    @Test("Duplicate policies receive the accumulated value and the incoming element")
    func resolution() {
        let items = [Entry(id: 1, value: 10), Entry(id: 1, value: 20), Entry(id: 1, value: 40)]
        let first = items.indexed(by: \.id) { _, current, _ in current }
        let last = items.indexed(by: \.id) { _, _, incoming in incoming }
        var currentValues: [Int] = []
        let combined = items.indexed(by: \.id) { id, current, incoming in
            currentValues.append(current.value)
            return Entry(id: id, value: current.value + incoming.value)
        }

        #expect(first[1]?.value == 10)
        #expect(last[1]?.value == 40)
        #expect(combined[1]?.value == 70)
        #expect(currentValues == [10, 30])
    }

    @Test("Indexing consumes a single-pass sequence and projects each element once")
    func singlePass() {
        let input = Cursor([Entry(id: 1, value: 10), Entry(id: 2, value: 20)])
        var projections: [Int] = []
        let index = input.indexed(by: { entry in
            projections.append(entry.id)
            return entry.id
        }) { _, current, _ in current }

        #expect(index.count == 2)
        #expect(input.iteratorCount == 1)
        #expect(projections == [1, 2])
    }

    @Test("Strict indexing stops at the first duplicate with both original occurrences")
    func firstDuplicate() {
        let first = Entry(id: 1, value: 10)
        let duplicate = Entry(id: 1, value: 20)
        let input = Cursor([first, duplicate, Entry(id: 2, value: 30)])
        var projections: [Int] = []
        #expect(throws: Duplicate(key: 1, first: first, incoming: duplicate)) {
            try input.indexedByUniqueKey({ entry in
                projections.append(entry.value)
                return entry.id
            }, duplicate: Duplicate.init)
        }

        #expect(input.iteratorCount == 1)
        #expect(input.position == 2)
        #expect(projections == [10, 20])
    }

    @Test("A throwing resolver preserves its error type and stops consuming input")
    func throwingResolver() {
        let first = Entry(id: 1, value: 10)
        let duplicate = Entry(id: 1, value: 20)
        let input = Cursor([first, duplicate, Entry(id: 2, value: 30)])

        func index() throws(Duplicate) -> [Int: Entry] {
            try input.indexed(by: \.id) { (key, current, incoming) throws(Duplicate) in
                throw Duplicate(key: key, first: current, incoming: incoming)
            }
        }

        #expect(throws: Duplicate(key: 1, first: first, incoming: duplicate)) {
            try index()
        }
        #expect(input.position == 2)
    }

    @Test("Optional keys and nil values remain entries and participate in collisions")
    func optionalValues() throws {
        let input: [Int?] = [nil, nil, 3]
        var collisions = 0
        let index = input.indexed(by: { $0 }) { _, current, _ in
            collisions += 1
            return current
        }

        #expect(index.count == 2)
        #expect(collisions == 1)
        let value = try #require(index[nil])
        #expect(value == nil)
        #expect(index[3] == .some(.some(3)))
    }

    @Test("A rejected insertion leaves the accumulated lookup unchanged")
    func rejectedInsertion() throws {
        let first = Entry(id: 1, value: 10)
        let duplicate = Entry(id: 1, value: 20)
        var index = IndexBuilder<Int, Entry>()
        try index.insert(first, forKey: 1, duplicate: Duplicate.init)

        #expect(throws: Duplicate(key: 1, first: first, incoming: duplicate)) {
            try index.insert(duplicate, forKey: 1, duplicate: Duplicate.init)
        }
        #expect(index.values == [1: first])
        try index.insert(Entry(id: 2, value: 30), forKey: 2, duplicate: Duplicate.init)
        #expect(index.values.count == 2)
    }

    private func strictIndex(_ items: [Entry]) throws(Duplicate) -> [Int: Entry] {
        try items.indexedByUniqueKey(\.id) { key, first, incoming in
            Duplicate(key: key, first: first, incoming: incoming)
        }
    }
}

private struct Entry: Equatable, Sendable {
    let id: Int
    let value: Int
}

private struct Duplicate: Error, Equatable {
    let key: Int
    let first: Entry
    let incoming: Entry
}

private final class Cursor: Sequence, IteratorProtocol {
    let entries: [Entry]
    var position = 0
    var iteratorCount = 0

    init(_ entries: [Entry]) {
        self.entries = entries
    }

    func makeIterator() -> Cursor {
        iteratorCount += 1
        return self
    }

    func next() -> Entry? {
        guard position < entries.count else { return nil }
        defer { position += 1 }
        return entries[position]
    }
}
