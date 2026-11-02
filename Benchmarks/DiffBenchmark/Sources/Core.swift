// Created by weixi on 2026/09/17.
import Foundation

struct BenchItem<ID: Hashable>: Equatable, Differentiable {
    let id: ID
    var revision: Int = 0
    var differenceIdentifier: ID { id }
    func isContentEqual(to source: Self) -> Bool { revision == source.revision }
}

struct BenchMove { let from: Int; let to: Int }
struct BenchPlan {
    // Deletes, updates and move sources refer to old; inserts and destinations to new.
    var deletes: [Int] = []
    var inserts: [Int] = []
    var moves: [BenchMove] = []
    var updates: [Int] = []
    var operationCount: Int { deletes.count + inserts.count + moves.count + updates.count }
}

enum BenchEngine: String, CaseIterable {
    case differenceKit = "DifferenceKit-core"
    case heckel = "Unique-Heckel"
    case lis = "Key-LIS"
    case standard = "Swift-difference"
}

// Unique IDs make Heckel's occurrence matching unambiguous. The move selection
// below follows the next-unconsumed-source policy, without duplicate matching.
// LIS shares the same identity/content pass and changes only stationary selection.
func keyedPlan<ID>(_ old: [BenchItem<ID>], _ new: [BenchItem<ID>], lis: Bool) -> BenchPlan {
    let index = Dictionary(uniqueKeysWithValues: old.enumerated().map { ($0.element.id, $0.offset) })
    var references = [Int](repeating: -1, count: new.count)
    var matched = [Bool](repeating: false, count: old.count)
    var plan = BenchPlan()
    for j in new.indices {
        if let i = index[new[j].id] {
            references[j] = i
            matched[i] = true
            if old[i].revision != new[j].revision { plan.updates.append(i) }
        } else { plan.inserts.append(j) }
    }
    for i in old.indices where !matched[i] { plan.deletes.append(i) }
    if lis {
        var tails: [Int] = []  // New indices, ordered by referenced old index.
        var previous = [Int](repeating: -1, count: new.count)
        var last = -1
        var increasing = true
        for i in references where i >= 0 {
            if i < last { increasing = false; break }
            last = i
        }
        // Same-order survivors need no moves (append/prepend/filter/no-op).
        if increasing { return plan }
        for j in new.indices where references[j] >= 0 {
            var lo = 0, hi = tails.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if references[tails[mid]] < references[j] { lo = mid + 1 } else { hi = mid }
            }
            if lo > 0 { previous[j] = tails[lo - 1] }
            if lo == tails.count { tails.append(j) } else { tails[lo] = j }
        }
        var stationary = [Bool](repeating: false, count: new.count)
        var cursor = tails.last ?? -1
        while cursor >= 0 { stationary[cursor] = true; cursor = previous[cursor] }
        for j in new.indices where references[j] >= 0 && !stationary[j] {
            plan.moves.append(BenchMove(from: references[j], to: j))
        }
    } else {
        var consumed = matched.map { !$0 }
        var cursor = 0
        for j in new.indices where references[j] >= 0 {
            while cursor < old.count && consumed[cursor] { cursor += 1 }
            let i = references[j]
            if i != cursor { plan.moves.append(BenchMove(from: i, to: j)) }
            consumed[i] = true
        }
    }
    return plan
}

func makePlan<ID>(_ engine: BenchEngine, _ old: [BenchItem<ID>], _ new: [BenchItem<ID>]) -> BenchPlan {
    switch engine {
    case .heckel: return keyedPlan(old, new, lis: false)
    case .lis: return keyedPlan(old, new, lis: true)
    case .differenceKit:
        // Internal entry point is intentionally pinned to the research checkout.
        // Include conversion to the same old/new coordinate contract in timing.
        let raw = diff(source: ContiguousArray(old), target: ContiguousArray(new),
                       useTargetIndexForUpdated: false, mapIndex: { $0 })
        let survivors = old.indices.filter { raw.sourceTraces[$0].reference != nil }
        return BenchPlan(deletes: raw.deleted, inserts: raw.inserted,
                         moves: raw.moved.map { BenchMove(from: survivors[$0.source], to: $0.target) },
                         updates: raw.updated)
    case .standard:
        let delta = new.map(\.id).difference(from: old.map(\.id)).inferringMoves()
        var plan = BenchPlan()
        for change in delta {
            switch change {
            case .remove(let offset, _, let associated):
                if let j = associated { plan.moves.append(BenchMove(from: offset, to: j)) }
                else { plan.deletes.append(offset) }
            case .insert(let offset, _, let associated):
                if associated == nil { plan.inserts.append(offset) }
            }
        }
        let target = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0.revision) })
        for i in old.indices {
            if let revision = target[old[i].id], revision != old[i].revision { plan.updates.append(i) }
        }
        return plan
    }
}

func customStages<ID>(_ plan: BenchPlan, _ old: [BenchItem<ID>], _ new: [BenchItem<ID>]) -> [Changeset<[BenchItem<ID>]>] {
    let target = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
    var stages: [Changeset<[BenchItem<ID>]>] = []
    var current = old
    if !plan.updates.isEmpty {
        for i in plan.updates { current[i] = target[old[i].id]! }
        stages.append(Changeset(data: current, elementUpdated: plan.updates.map { ElementPath(element: $0, section: 0) }))
    }
    let deleted = Set(plan.deletes)
    var survivorIndex = [Int](repeating: -1, count: old.count)
    var nextIndex = 0
    for i in old.indices where !deleted.contains(i) { survivorIndex[i] = nextIndex; nextIndex += 1 }
    if !plan.deletes.isEmpty {
        current = current.enumerated().filter { !deleted.contains($0.offset) }.map(\.element)
        stages.append(Changeset(data: current, elementDeleted: plan.deletes.map { ElementPath(element: $0, section: 0) }))
    }
    if !plan.inserts.isEmpty || !plan.moves.isEmpty {
        stages.append(Changeset(data: new,
            elementInserted: plan.inserts.map { ElementPath(element: $0, section: 0) },
            elementMoved: plan.moves.map { (ElementPath(element: survivorIndex[$0.from], section: 0), ElementPath(element: $0.to, section: 0)) }))
    }
    return stages
}

struct BenchRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

struct BenchFixture<ID: Hashable> {
    let name: String
    let old: [BenchItem<ID>]
    let new: [BenchItem<ID>]
}

func fixtures(_ count: Int, seed: UInt64 = 0x504152414445) -> [BenchFixture<Int>] {
    let old = (0..<count).map { BenchItem(id: $0) }
    let amount = max(1, count / 20)
    let extra = (count..<(count + amount)).map { BenchItem(id: $0) }
    var output: [BenchFixture<Int>] = []
    func add(_ name: String, _ new: [BenchItem<Int>]) { output.append(.init(name: name, old: old, new: new)) }
    add("no-op", old)
    add("append-5pct", old + extra)
    add("prepend-5pct", extra + old)
    add("delete-5pct", old.filter { $0.id % 20 != 0 })
    add("rotate-left-1", Array(old.dropFirst()) + Array(old.prefix(1)))
    add("rotate-right-1", Array(old.suffix(1)) + Array(old.dropLast()))
    var updated = old
    for i in stride(from: 0, to: count, by: 20) { updated[i].revision += 1 }
    add("update-5pct", updated)
    var swap = old
    if count > 1 { swap.swapAt(count / 2 - 1, count / 2) }
    add("adjacent-swap", swap)
    var rng = BenchRNG(state: seed ^ UInt64(count))
    var shuffled = old; shuffled.shuffle(using: &rng)
    add("shuffle", shuffled)
    add("reverse", Array(old.reversed()))
    add("replace-all", (count..<(2 * count)).map { BenchItem(id: $0) })
    var mixed = updated.filter { $0.id % 20 != 1 }
    mixed.insert(contentsOf: extra, at: min(mixed.count, count / 3))
    let block = min(amount, mixed.count)
    mixed = Array(mixed.dropFirst(block)) + Array(mixed.prefix(block))
    add("mixed", mixed)
    return output
}

func stringFixture(_ f: BenchFixture<Int>) -> BenchFixture<String> {
    func convert(_ item: BenchItem<Int>) -> BenchItem<String> {
        BenchItem(id: "section-0:item-\(item.id)", revision: item.revision)
    }
    return .init(name: f.name, old: f.old.map(convert), new: f.new.map(convert))
}

// Independently replay simultaneous old/new-coordinate edits. Never accept a
// result just because its stored target equals the fixture's target.
func validate<ID>(_ plan: BenchPlan, _ old: [BenchItem<ID>], _ new: [BenchItem<ID>]) {
    let oldIDs = Set(old.map(\.id)), newIDs = Set(new.map(\.id))
    precondition(oldIDs.count == old.count && newIDs.count == new.count)
    precondition(Set(plan.deletes) == Set(old.indices.filter { !newIDs.contains(old[$0].id) }))
    precondition(Set(plan.inserts) == Set(new.indices.filter { !oldIDs.contains(new[$0].id) }))
    let targets = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
    precondition(Set(plan.updates) == Set(old.indices.filter { i in targets[old[i].id].map { $0.revision != old[i].revision } ?? false }))
    precondition(Set(plan.deletes).count == plan.deletes.count && Set(plan.inserts).count == plan.inserts.count)
    precondition(Set(plan.moves.map(\.from)).count == plan.moves.count && Set(plan.moves.map(\.to)).count == plan.moves.count)
    var removed = Set(plan.deletes)
    var rebuilt = [BenchItem<ID>?](repeating: nil, count: new.count)
    for j in plan.inserts { rebuilt[j] = new[j] }
    for move in plan.moves {
        precondition(old.indices.contains(move.from) && new.indices.contains(move.to))
        precondition(!removed.contains(move.from) && rebuilt[move.to] == nil)
        precondition(old[move.from].id == new[move.to].id)
        rebuilt[move.to] = targets[old[move.from].id]!
        removed.insert(move.from)
    }
    var retained = old.indices.filter { !removed.contains($0) }.makeIterator()
    for j in new.indices where rebuilt[j] == nil { rebuilt[j] = targets[old[retained.next()!].id]! }
    precondition(retained.next() == nil && rebuilt.compactMap { $0 } == new)
}

func validateStages<ID>(_ stages: [Changeset<[BenchItem<ID>]>], _ old: [BenchItem<ID>], _ new: [BenchItem<ID>]) {
    var current = old
    for stage in stages {
        validate(BenchPlan(deletes: stage.elementDeleted.map(\.element), inserts: stage.elementInserted.map(\.element),
                           moves: stage.elementMoved.map { BenchMove(from: $0.source.element, to: $0.target.element) },
                           updates: stage.elementUpdated.map(\.element)), current, stage.data)
        current = stage.data
    }
    precondition(current == new)
}

func lcsOracle(_ a: [Int], _ b: [Int]) -> Int {
    var row = [Int](repeating: 0, count: b.count + 1)
    for x in a {
        var previous = 0
        for j in b.indices {
            let saved = row[j + 1]
            row[j + 1] = x == b[j] ? previous + 1 : max(row[j], row[j + 1])
            previous = saved
        }
    }
    return row.last!
}

func verifyCore() -> Int {
    var rng = BenchRNG(state: 0x766572696679)
    var count = 0
    func check(_ old: [BenchItem<Int>], _ new: [BenchItem<Int>]) {
        for engine in BenchEngine.allCases {
            let p = makePlan(engine, old, new)
            validate(p, old, new)
            validateStages(customStages(p, old, new), old, new)
            if engine == .lis || engine == .standard {
                let shared = Set(old.map(\.id)).intersection(new.map(\.id)).count
                precondition(p.moves.count == shared - lcsOracle(old.map(\.id), new.map(\.id)))
            }
            count += 1
        }
        validateStages(Array(StagedChangeset(source: old, target: new)), old, new)
    }
    // Every permutation through length 7, with an independent quadratic oracle.
    func permute(_ values: [Int], _ prefix: [Int], _ full: [BenchItem<Int>]) {
        if values.isEmpty { check(full, prefix.map { BenchItem(id: $0) }); return }
        for i in values.indices { var rest = values; let v = rest.remove(at: i); permute(rest, prefix + [v], full) }
    }
    for n in 0...7 { permute(Array(0..<n), [], (0..<n).map { BenchItem(id: $0) }) }
    for _ in 0..<1500 {
        let universe = Array(0..<Int(rng.next() % 35))
        var a = universe.filter { _ in rng.next() % 4 != 0 }
        var b = universe.filter { _ in rng.next() % 4 != 0 }
        a.shuffle(using: &rng); b.shuffle(using: &rng)
        check(a.map { BenchItem(id: $0) }, b.map { BenchItem(id: $0, revision: Int(rng.next() % 3)) })
    }
    return count
}

func nanos() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
func percentile(_ values: [Double], _ p: Double) -> Double {
    let sorted = values.sorted()
    return sorted[min(sorted.count - 1, max(0, Int(ceil(Double(sorted.count) * p)) - 1))]
}

@inline(never) func consume(_ plan: BenchPlan) -> Int {
    var value = plan.operationCount
    for m in plan.moves { value &+= m.from &+ m.to }
    for i in plan.inserts { value &+= i }
    for i in plan.deletes { value &+= i }
    for i in plan.updates { value &+= i }
    return value
}
