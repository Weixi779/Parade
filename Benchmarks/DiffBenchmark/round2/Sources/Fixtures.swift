// Created by weixi on 2026/09/17.
import Foundation

struct UIFixture {
    let name: String
    let old: [UISection]
    let new: [UISection]
    let group: String
    var requestedFraction: Double = 0
    var seed: UInt64 = 0
    var count: Int { old.reduce(0) { $0 + $1.elements.count } }
}

func matrixFixtures(_ size: Int) -> [UIFixture] {
    let old = (0..<3).map { s in UISection(model: UIHeader(id: s),
        elements: (0..<size).map { UIItem(id: "original-s\(s):i\($0)") }) }
    var fixtures: [UIFixture] = []
    func add(_ name: String, _ new: [UISection]) { fixtures.append(.init(name: name, old: old, new: new, group: "matrix")) }
    add("section-rotate-right", [old[2],old[0],old[1]])
    add("section-rotate-left", [old[1],old[2],old[0]])
    var next = [old[2],old[0],old[1]]
    next[0].elements.append(next[0].elements.removeFirst())
    add("section-move-and-local-reorder", next)
    next[0].elements[next[0].elements.count - 1].revision += 1
    add("section-move-local-reorder-update", next)
    next = [old[2],old[0],old[1]]
    next[0].elements[0].revision += 1
    add("section-move-and-item-update", next)
    next = [old[2],old[0],old[1]]
    next[2].elements.insert(next[1].elements.removeFirst(), at: 0)
    add("section-move-and-cross-section-move", next)
    next[2].elements[0].revision += 1
    add("section-move-cross-section-move-update", next)
    next = old
    next[0].elements.insert(next[0].elements.removeLast(), at: 0)
    next[0].elements[0].revision += 1
    add("move-and-update", next)
    next = old
    var escaped = next[0].elements.removeFirst(); escaped.revision += 1
    next[1].elements.insert(escaped, at: 0)
    add("cross-section-move-update", next)
    next = old; next[1].elements.insert(next[0].elements[0], at: 0); next.removeFirst()
    add("escape-deleted-section", next)
    next[0].elements[0].revision += 1
    add("escape-deleted-section-update", next)
    next = old
    let entering = next[0].elements.removeFirst()
    next.insert(UISection(model: UIHeader(id: 8), elements: [entering, UIItem(id: "new-item")]), at: 1)
    add("enter-inserted-section", next)
    next[1].elements[0].revision += 1
    add("enter-inserted-section-update", next)
    next = old
    let transfer = next.removeFirst().elements[0]
    next.insert(UISection(model: UIHeader(id: 8), elements: [transfer,UIItem(id: "new-item")]), at: 0)
    add("deleted-to-inserted-section", next)
    next[0].elements[0].revision += 1
    add("deleted-to-inserted-section-update", next)
    next = old
    let a = next[0].elements.removeFirst(), b = next[1].elements.removeFirst(), c = next[2].elements.removeFirst()
    next[0].elements.insert(c, at: 0); next[1].elements.insert(a, at: 0); next[2].elements.insert(b, at: 0)
    add("three-way-cross-section-cycle", next)
    add("section-delete-without-item-deletes", Array(old.dropFirst()))
    add("section-insert-without-item-inserts", [UISection(model: UIHeader(id: 8),elements: [UIItem(id: "new-only")])] + old)
    add("replace-all-sections-preserve-items", old.enumerated().map { i, s in UISection(model: UIHeader(id: i + 10), elements: s.elements) })
    add("replace-all-sections-new-identities", (10..<13).map { s in UISection(model: UIHeader(id: s),elements: (0..<size).map { UIItem(id:"new-s\(s):i\($0)") }) })
    return fixtures
}

func permutations(_ n: Int) -> [(String,[Int])] {
    let a = Array(0..<n)
    var result: [(String,[Int])] = []
    for k in [1,2,10,n/2,n-1] { result.append(("rotate-\(k)", Array(a.dropFirst(k)) + Array(a.prefix(k)))) }
    let q = n/4
    result.append(("block-move",Array(a[q..<(2*q)]) + Array(a[..<q]) + Array(a[(2*q)...])))
    result.append(("block-swap",Array(a[(3*q)...]) + Array(a[q..<(3*q)]) + Array(a[..<q])))
    var interleaved: [Int] = []
    let midpoint = n/2
    for i in 0..<midpoint { interleaved.append(i); interleaved.append(i + midpoint) }
    if n % 2 != 0 { interleaved.append(n-1) }
    result.append(("interleave", interleaved))
    result.append(("odd-even", a.filter { $0 % 2 != 0 } + a.filter { $0 % 2 == 0 }))
    var middle = a; let value = middle.remove(at: n/2); middle.insert(value, at: 0)
    result.append(("middle-to-head", middle))
    let chunk = n/8
    let order = [1,0,3,2,5,4,7,6]
    result.append(("disjoint-block-swaps", order.flatMap { Array(a[($0*chunk)..<(($0+1)*chunk)]) } + Array(a[(8*chunk)...])))
    result.append(("reverse", Array(a.reversed())))
    return result
}

// Independent maximum-length oracle using a Fenwick tree, unlike the planner's
// binary-search tails + predecessor reconstruction. Inputs are permutations.
func permutationLISLength(_ values: [Int]) -> Int {
    var tree = [Int](repeating: 0, count: values.count + 2)
    var best = 0
    for value in values {
        var p = value, prefix = 0
        while p > 0 { prefix = max(prefix, tree[p]); p -= p & -p }
        let length = prefix + 1
        p = value + 1
        while p < tree.count { tree[p] = max(tree[p],length); p += p & -p }
        best = max(best,length)
    }
    return best
}

func permutationFixtures(_ n: Int) -> [UIFixture] {
    let old = (0..<n).map { UIItem(id: "item-\($0)") }
    return permutations(n).map { name, order in
        .init(name: name,old:[UISection(model:UIHeader(id:0),elements:old)],
              new:[UISection(model:UIHeader(id:0),elements:order.map { old[$0] })],group:"permutation")
    }
}

func churnFixtures(_ n: Int) -> [UIFixture] {
    let old = (0..<n).map { UIItem(id:"item-\($0)") }
    var result: [UIFixture] = []
    for seed: UInt64 in [117,229,353] {
        for pct in [0,10,25,50,75,90,100] {
            var rng = BenchRNG(state: seed ^ UInt64(n))
            var locations = Array(0..<n); locations.shuffle(using: &rng)
            let selected = Array(locations.prefix(n * pct / 100)).sorted()
            var reordered = selected; reordered.shuffle(using: &rng)
            var next = old
            for (i,j) in zip(selected,reordered) { next[i] = old[j] }
            result.append(.init(name:"shuffle-\(pct)pct-seed\(seed)",old:[UISection(model:UIHeader(id:0),elements:old)],
                new:[UISection(model:UIHeader(id:0),elements:next)],group:"churn",requestedFraction:Double(pct)/100,seed:seed))
        }
    }
    return result
}

func randomizedSectionFixtures(_ count: Int) -> [UIFixture] {
    var rng = BenchRNG(state: 0x73656374696f6e)
    func state() -> [UISection] {
        var headers = Array(0..<5).filter { _ in rng.next() % 3 != 0 }
        headers.shuffle(using: &rng)
        var sections = headers.map { UISection(model:UIHeader(id:$0),elements: [UIItem]()) }
        if !sections.isEmpty {
            for id in 0..<15 where rng.next() % 4 != 0 {
                let s = Int(rng.next() % UInt64(sections.count))
                sections[s].elements.append(UIItem(id:"r-\(id)",revision:Int(rng.next()%3)))
            }
            for s in sections.indices { sections[s].elements.shuffle(using:&rng) }
        }
        return sections
    }
    return (0..<count).map { .init(name:"random-\($0)",old:state(),new:state(),group:"random") }
}
