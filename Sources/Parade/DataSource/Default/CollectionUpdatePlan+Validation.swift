// Created by weixi on 2026/09/17.

import Foundation

extension CollectionUpdatePlan {
    /// Reject invalid external algorithm results before using their coordinates.
    /// Content equality remains the algorithm's responsibility.
    static func validate(
        _ changes: SectionedChanges,
        from source: [CapturedSection],
        to target: [CapturedSection],
        sourcePositions: CollectionPositions<AnyHashable, AnyHashable>,
        targetPositions: CollectionPositions<AnyHashable, AnyHashable>
    ) throws {
        try require(changes.deletedSections == IndexSet(source.indices.filter {
            targetPositions.sectionIndices[source[$0].id] == nil
        }), "Section deletions must contain exactly the removed identities")
        try require(changes.insertedSections == IndexSet(target.indices.filter {
            sourcePositions.sectionIndices[target[$0].id] == nil
        }), "Section insertions must contain exactly the new identities")
        let removedItems = Set(sourcePositions.itemLocations.compactMap { id, location in
            targetPositions.itemLocations[id] == nil ? location : nil
        })
        let addedItems = Set(targetPositions.itemLocations.compactMap { id, location in
            sourcePositions.itemLocations[id] == nil ? location : nil
        })
        try require(Set(changes.deletedItems) == removedItems && changes.deletedItems.count == removedItems.count,
                    "Item deletions must contain exactly the removed identities")
        try require(Set(changes.insertedItems) == addedItems && changes.insertedItems.count == addedItems.count,
                    "Item insertions must contain exactly the new identities")
        var sectionSources = Set<Int>()
        var sectionDestinations = Set<Int>()
        for move in changes.movedSections {
            try require(
                source.indices.contains(move.from) && target.indices.contains(move.to),
                "Invalid section move"
            )
            try require(source[move.from].id == target[move.to].id, "Section move changes identity")
            try require(
                sectionSources.insert(move.from).inserted && sectionDestinations.insert(move.to)
                    .inserted,
                "Conflicting section moves"
            )
        }
        var itemSources = Set<ItemLocation>()
        var itemDestinations = Set<ItemLocation>()
        for move in changes.movedItems {
            try require(
                contains(move.from, in: source) && contains(move.to, in: target),
                "Invalid item move"
            )
            try require(
                source[move.from.section].cells[move.from.item].id == target[move.to.section]
                    .cells[move.to.item].id,
                "Item move changes identity"
            )
            try require(
                itemSources.insert(move.from).inserted && itemDestinations.insert(move.to).inserted,
                "Conflicting item moves"
            )
        }
        for section in changes.updatedSections {
            try require(target.indices.contains(section), "Invalid section update")
            try require(
                sourcePositions.sectionIndices[target[section].id] != nil,
                "Updated section is not retained"
            )
        }
        var updates = Set<ItemLocation>()
        for item in changes.updatedItems {
            try require(
                contains(item, in: target) && updates.insert(item).inserted,
                "Invalid or repeated item update"
            )
            try require(
                sourcePositions.itemLocations[target[item.section].cells[item.item].id] != nil,
                "Updated item is not retained"
            )
        }
    }

    /// Replay actual batch operations against prior contents before touching UIKit.
    /// This catches valid-looking counts whose moves produce the wrong identities.
    static func validate(
        _ batches: [CollectionBatch],
        from source: [CapturedSection],
        to target: [CapturedSection]
    ) throws {
        _ = try CollectionPositions(source, input: .source)
        _ = try CollectionPositions(target, input: .target)
        var current = source
        for (index, batch) in batches.enumerated() {
            do {
                _ = try CollectionPositions(batch.sections, input: .target)
                let replayed = try batch.replaying(from: current)
                try require(
                    sameIdentities(replayed, batch.sections),
                    "Operations do not produce the declared batch"
                )
                current = replayed
            } catch {
                throw ValidationError("Batch \(index): \(error)")
            }
        }
        try require(sameIdentities(current, target), "Plan does not reach the target")
    }
}

private extension CollectionBatch {
    func replaying(
        from source: [CapturedSection]
    ) throws -> [CapturedSection] {
        try require(!isEmpty, "Empty batch")
        if !deletedSections.isEmpty || !insertedSections.isEmpty || !movedSections.isEmpty {
            try require(
                deletedItems.isEmpty && insertedItems.isEmpty && movedItems.isEmpty,
                "Section and item operations share a batch"
            )
            let count = source.count - deletedSections.count + insertedSections.count
            try require(count >= 0 && sections.count == count, "Invalid section count")
            var slots = [CapturedSection?](repeating: nil, count: count)
            var removed = Set<Int>()
            for origin in deletedSections {
                try require(
                    source.indices.contains(origin) && removed.insert(origin).inserted,
                    "Invalid or repeated section source"
                )
            }
            for destination in insertedSections {
                try require(slots.indices.contains(destination), "Invalid section destination")
                slots[destination] = sections[destination]
            }
            for move in movedSections {
                try require(
                    source.indices.contains(move.from) && slots.indices.contains(move.to),
                    "Invalid section move"
                )
                try require(
                    removed.insert(move.from).inserted && slots[move.to] == nil,
                    "Conflicting section move"
                )
                slots[move.to] = source[move.from]
            }
            var retained = source.indices.filter { !removed.contains($0) }.makeIterator()
            for destination in slots.indices where slots[destination] == nil {
                guard let origin = retained.next() else {
                    throw CollectionUpdatePlan.ValidationError("Missing retained section")
                }
                slots[destination] = source[origin]
            }
            try require(retained.next() == nil, "Extra retained section")
            return slots.compactMap { $0 }
        }

        try require(
            source.map(\.id) == sections.map(\.id),
            "Item batch changed section identities"
        )
        var removed = Set<ItemLocation>()
        var destinations = Set<ItemLocation>()
        var slots = sections.map { [AnyCellPresenter?](repeating: nil, count: $0.cells.count) }
        for origin in deletedItems {
            try require(
                contains(origin, in: source) && removed.insert(origin).inserted,
                "Invalid or repeated item source"
            )
        }
        for destination in insertedItems {
            try require(
                contains(destination, in: sections) &&
                    destinations.insert(destination).inserted,
                "Invalid or repeated item destination"
            )
            slots[destination.section][destination.item] =
                sections[destination.section].cells[destination.item]
        }
        for move in movedItems {
            try require(
                contains(move.from, in: source) && contains(move.to, in: sections),
                "Invalid item move"
            )
            try require(
                removed.insert(move.from).inserted && destinations.insert(move.to).inserted,
                "Conflicting item move"
            )
            slots[move.to.section][move.to.item] = source[move.from.section].cells[move.from.item]
        }
        for section in source.indices {
            var retained = source[section].cells.indices.filter {
                !removed.contains(ItemLocation(section: section, item: $0))
            }.makeIterator()
            for item in slots[section].indices where !destinations.contains(ItemLocation(
                section: section,
                item: item
            )) {
                guard let origin = retained.next() else {
                    throw CollectionUpdatePlan.ValidationError("Missing retained item")
                }
                slots[section][item] = source[section].cells[origin]
            }
            try require(retained.next() == nil, "Extra retained item")
        }
        return source.indices.map { index in
            source[index].replacingCells(slots[index].compactMap { $0 })
        }
    }

}

private func sameIdentities(_ lhs: [CapturedSection], _ rhs: [CapturedSection]) -> Bool {
    lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
        $0.id == $1.id && $0.cells.map(\.id) == $1.cells.map(\.id)
    }
}

private func contains(_ location: ItemLocation, in sections: [CapturedSection]) -> Bool {
    sections.indices.contains(location.section) &&
        sections[location.section].cells.indices.contains(location.item)
}

private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw CollectionUpdatePlan.ValidationError(message) }
}
