// Created by weixi on 2026/09/17.

/// Identity matching with a greedy next-unconsumed-source move policy. Matching
/// work and storage are expected linear in sections + items, in addition to the
/// input values' hashing and content-comparison costs. Moves need not be minimal.
public struct SectionedDiff: SectionedDiffAlgorithm {
    public init() {}

    public func diff<Section: DiffableSection>(
        from source: [Section],
        to target: [Section]
    ) throws -> SectionedChanges {
        let sourceIndex = try CollectionPositions(source, input: .source)
        let targetIndex = try CollectionPositions(target, input: .target)
        var changes = SectionedChanges()
        var sectionOrder = SourceOrder(count: source.count)
        for (section, value) in source.enumerated() {
            if targetIndex.sectionIndices[value.id] == nil {
                changes.deletedSections.insert(section)
                sectionOrder.consume(section)
            }
            for (item, value) in value.items.enumerated()
                where targetIndex.itemLocations[value.id] == nil {
                changes.deletedItems.append(ItemLocation(section: section, item: item))
            }
        }

        for (section, value) in target.enumerated() {
            let origin = sourceIndex.sectionIndices[value.id]
            if let origin {
                if origin != sectionOrder.next {
                    changes.movedSections.append((from: origin, to: section))
                }
                sectionOrder.consume(origin)
                if !source[origin].isContentEqual(to: value) {
                    changes.updatedSections.insert(section)
                }
            } else {
                changes.insertedSections.insert(section)
            }

            var itemOrder = SourceOrder(count: origin.map { source[$0].items.count } ?? 0)
            if let origin {
                for (item, old) in source[origin].items.enumerated() {
                    if let destination = targetIndex.itemLocations[old.id],
                       target[destination.section].id == value.id {
                        continue
                    }
                    itemOrder.consume(item)
                }
            }
            for (item, new) in value.items.enumerated() {
                let destination = ItemLocation(section: section, item: item)
                guard let old = sourceIndex.itemLocations[new.id] else {
                    changes.insertedItems.append(destination)
                    continue
                }
                if source[old.section].id != value.id {
                    changes.movedItems.append((from: old, to: destination))
                } else {
                    if old.item != itemOrder.next {
                        // A move can have equal numeric coordinates in a permutation.
                        changes.movedItems.append((from: old, to: destination))
                    }
                    itemOrder.consume(old.item)
                }
                if source[old.section].items[old.item] != new {
                    changes.updatedItems.append(destination)
                }
            }
        }
        return changes
    }
}

/// Tracks the earliest source position still eligible to remain stationary.
/// Each position is scanned at most once, even when later positions move first.
private struct SourceOrder {
    private var consumed: [Bool]
    private(set) var next = 0

    init(count: Int) {
        consumed = [Bool](repeating: false, count: count)
    }

    mutating func consume(_ position: Int) {
        consumed[position] = true
        while next < consumed.count && consumed[next] { next += 1 }
    }
}
