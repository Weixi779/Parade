// Created by weixi on 2026/09/17.
import Foundation

typealias UIItem = BenchItem<String>
struct UIHeader: Differentiable, Equatable {
    let id: Int
    var differenceIdentifier: Int { id }
}
typealias UISection = ArraySection<UIHeader, UIItem>

enum ContentTiming { case before, after }
struct SectionStage {
    let name: String
    let changes: Changeset<[UISection]>
    var contentOnly: Bool { !changes.elementUpdated.isEmpty }
}

struct ItemLocation {
    let sectionID: Int
    let section: Int
    let item: Int
    let value: UIItem
    var path: ElementPath { ElementPath(element: item, section: section) }
}

func itemLocations(_ sections: [UISection]) -> [String: ItemLocation] {
    var result: [String: ItemLocation] = [:]
    result.reserveCapacity(sections.reduce(0) { $0 + $1.elements.count })
    for (s, section) in sections.enumerated() {
        for (i, value) in section.elements.enumerated() {
            precondition(result.updateValue(ItemLocation(sectionID: section.model.id, section: s, item: i, value: value), forKey: value.id) == nil,
                         "Duplicate presentation ID")
        }
    }
    return result
}

// Research planner. Keep section identity distinct from its changing position.
// Separate section edits from item edits; allow survivor items to leave doomed
// sections and enter newly inserted sections without destroying their identity.
func sectionPlan(_ old: [UISection], _ new: [UISection], content: ContentTiming) -> [SectionStage] {
    let original = itemLocations(old)
    let target = itemLocations(new)
    let targetSections = Dictionary(uniqueKeysWithValues: new.map { ($0.model.id, $0) })
    let oldSectionIDs = Set(old.map { $0.model.id })
    let targetSectionIDs = Set(new.map { $0.model.id })
    var current = old
    var result: [SectionStage] = []
    func commit(_ name: String, _ change: Changeset<[UISection]>) {
        precondition(change.changeCount > 0)
        result.append(SectionStage(name: name, changes: change))
        current = change.data
    }
    func contentUpdate() {
        var data = current
        var paths: [ElementPath] = []
        for s in data.indices {
            for i in data[s].elements.indices {
                let value = data[s].elements[i]
                if let desired = target[value.id]?.value, desired.revision != value.revision {
                    data[s].elements[i] = desired
                    paths.append(ElementPath(element: i, section: s))
                }
            }
        }
        if !paths.isEmpty { commit("content", Changeset(data: data, elementUpdated: paths)) }
    }
    if content == .before { contentUpdate() }

    // Populate new sections only with genuinely new identities. Incoming
    // survivors remain in their old sections until the item-transfer stage.
    var insertedData = current
    for j in new.indices.reversed() where !oldSectionIDs.contains(new[j].model.id) {
        let nextID = new.indices.dropFirst(j + 1).map { new[$0].model.id }.first {
            id in insertedData.contains { $0.model.id == id }
        }
        let index = nextID.flatMap { id in insertedData.firstIndex { $0.model.id == id } } ?? insertedData.count
        insertedData.insert(UISection(model: new[j].model,
            elements: new[j].elements.filter { original[$0.id] == nil }), at: index)
    }
    let inserted = insertedData.indices.filter { !oldSectionIDs.contains(insertedData[$0].model.id) }
    if !inserted.isEmpty { commit("insert-sections", Changeset(data: insertedData, sectionInserted: inserted)) }

    // Preserve old content through structure-only stages when updating afterward.
    let live = itemLocations(current)
    let itemGoal = current.map { section -> UISection in
        if let desired = targetSections[section.model.id] {
            return UISection(model: section.model, elements: desired.elements.map { live[$0.id]?.value ?? $0 })
        }
        // True removals in deleted sections are implicit in section deletion.
        // Only surviving identities leave these sections explicitly.
        return UISection(model: section.model, elements: section.elements.filter { target[$0.id] == nil })
    }
    let goalItems = itemLocations(itemGoal)
    var afterDeletes = current
    var deletedItems: [ElementPath] = []
    for s in current.indices {
        for i in current[s].elements.indices where goalItems[current[s].elements[i].id] == nil {
            deletedItems.append(ElementPath(element: i, section: s))
        }
        afterDeletes[s].elements.removeAll { goalItems[$0.id] == nil }
    }
    if !deletedItems.isEmpty { commit("delete-items", Changeset(data: afterDeletes, elementDeleted: deletedItems)) }

    let sourceItems = itemLocations(current)
    var inserts: [ElementPath] = []
    var moves: [(source: ElementPath, target: ElementPath)] = []
    for (s, section) in itemGoal.enumerated() {
        let from = current[s].elements.filter { value in goalItems[value.id]?.sectionID == section.model.id }
        let to = section.elements.filter { value in sourceItems[value.id]?.sectionID == section.model.id }
        // Cross-section moves are mandatory under stable global item identity.
        // LIS only chooses the stationary same-section subsequence.
        let local = keyedPlan(from, to, lis: true)
        for move in local.moves {
            let id = from[move.from].id
            moves.append((sourceItems[id]!.path, goalItems[id]!.path))
        }
        for (i, value) in section.elements.enumerated() {
            let destination = ElementPath(element: i, section: s)
            if let source = sourceItems[value.id] {
                if source.sectionID != section.model.id { moves.append((source.path, destination)) }
            } else { inserts.append(destination) }
        }
    }
    if !inserts.isEmpty || !moves.isEmpty {
        commit("insert-and-move-items", Changeset(data: itemGoal, elementInserted: inserts, elementMoved: moves))
    }
    precondition(current == itemGoal)

    let deletedSections = current.indices.filter { !targetSectionIDs.contains(current[$0].model.id) }
    if !deletedSections.isEmpty {
        commit("delete-sections", Changeset(data: current.filter { targetSectionIDs.contains($0.model.id) }, sectionDeleted: deletedSections))
    }
    let currentSections = Dictionary(uniqueKeysWithValues: current.map { ($0.model.id, $0) })
    let reordered = new.map { currentSections[$0.model.id]! }
    let sectionMoves = keyedPlan(current.map { BenchItem(id: $0.model.id) },
                                  reordered.map { BenchItem(id: $0.model.id) }, lis: true).moves
    if !sectionMoves.isEmpty {
        commit("move-sections", Changeset(data: reordered, sectionMoved: sectionMoves.map { ($0.from, $0.to) }))
    }
    if content == .after { contentUpdate() }
    precondition(current == new, "Planner did not reach the requested state")
    return result
}

// Independent semantic replay for section and item coordinates, including
// implicit insertion/deletion of items owned by inserted/deleted sections.
func replaySectionStage(_ old: [UISection], _ change: Changeset<[UISection]>) -> [UISection] {
    let new = change.data
    let oldItems = itemLocations(old), newItems = itemLocations(new)
    precondition(change.sectionUpdated.isEmpty, "Header content is outside this experiment")
    let sectionPlan = BenchPlan(deletes: change.sectionDeleted, inserts: change.sectionInserted,
        moves: change.sectionMoved.map { BenchMove(from: $0.source, to: $0.target) })
    validate(sectionPlan, old.map { BenchItem(id: $0.model.id) }, new.map { BenchItem(id: $0.model.id) })
    let removedSections = Set(change.sectionDeleted), addedSections = Set(change.sectionInserted)
    func code(_ path: ElementPath) -> String { "\(path.section):\(path.element)" }
    let deleted = Set(change.elementDeleted.map(code))
    let moved = Set(change.elementMoved.map { code($0.source) })
    let updates = Set(change.elementUpdated.map { path -> String in
        precondition(old.indices.contains(path.section) && old[path.section].elements.indices.contains(path.element))
        return old[path.section].elements[path.element].id
    })
    precondition(deleted.count == change.elementDeleted.count && moved.count == change.elementMoved.count)
    precondition(updates.count == change.elementUpdated.count && deleted.isDisjoint(with: moved))
    for path in change.elementDeleted {
        precondition(old.indices.contains(path.section) && old[path.section].elements.indices.contains(path.element))
        precondition(!removedSections.contains(path.section))
    }
    var slots = new.map { [UIItem?](repeating: nil, count: $0.elements.count) }
    for s in addedSections { slots[s] = new[s].elements.map { Optional($0) } }
    func updated(_ value: UIItem) -> UIItem {
        updates.contains(value.id) ? newItems[value.id]!.value : value
    }
    for path in change.elementInserted {
        precondition(slots.indices.contains(path.section) && slots[path.section].indices.contains(path.element))
        precondition(slots[path.section][path.element] == nil)
        slots[path.section][path.element] = new[path.section].elements[path.element]
    }
    for move in change.elementMoved {
        precondition(!removedSections.contains(move.source.section) && !addedSections.contains(move.target.section))
        let item = old[move.source.section].elements[move.source.element]
        precondition(slots[move.target.section][move.target.element] == nil)
        slots[move.target.section][move.target.element] = updated(item)
    }
    let newSectionIndex = Dictionary(uniqueKeysWithValues: new.enumerated().map { ($0.element.model.id, $0.offset) })
    for s in old.indices where !removedSections.contains(s) {
        let destination = newSectionIndex[old[s].model.id]!
        var remaining = old[s].elements.enumerated().filter {
            let key = "\(s):\($0.offset)"; return !deleted.contains(key) && !moved.contains(key)
        }.map { updated($0.element) }.makeIterator()
        for i in slots[destination].indices where slots[destination][i] == nil {
            guard let item = remaining.next() else { preconditionFailure("Too few retained items") }
            slots[destination][i] = item
        }
        precondition(remaining.next() == nil, "Too many retained items")
    }
    for id in updates { precondition(oldItems[id] != nil && newItems[id] != nil) }
    let replayed = new.indices.map { s in UISection(model: new[s].model, elements: slots[s].map { $0! }) }
    precondition(replayed == new, "Section stage replay failed")
    return replayed
}

func validateSectionPlan(_ old: [UISection], _ new: [UISection], _ stages: [SectionStage]) {
    var state = old
    for stage in stages { state = replaySectionStage(state, stage.changes) }
    precondition(state == new)
}

func operationCounts(_ stages: [SectionStage]) -> [String: Int] {
    var counts = ["sectionInserts":0,"sectionDeletes":0,"sectionMoves":0,
                  "itemInserts":0,"itemDeletes":0,"itemMoves":0,"updates":0,"stages":stages.count]
    for stage in stages {
        let c = stage.changes
        counts["sectionInserts"]! += c.sectionInserted.count
        counts["sectionDeletes"]! += c.sectionDeleted.count
        counts["sectionMoves"]! += c.sectionMoved.count
        counts["itemInserts"]! += c.elementInserted.count
        counts["itemDeletes"]! += c.elementDeleted.count
        counts["itemMoves"]! += c.elementMoved.count
        counts["updates"]! += c.elementUpdated.count
    }
    return counts
}
