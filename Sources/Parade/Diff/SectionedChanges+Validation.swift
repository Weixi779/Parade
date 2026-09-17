// Created by weixi on 2026/09/17.

import Foundation

extension SectionedChanges {
    /// Check an external result before its coordinates are used for planning.
    /// Replay then verifies move completeness/order. Content equality is the
    /// algorithm's contract, not recomputed by this structural validation.
    func validate<SectionId: Hashable, ItemId: Hashable>(
        from source: [SectionStructure<SectionId, ItemId>],
        to target: [SectionStructure<SectionId, ItemId>],
        sourceIndex: DiffIndex<SectionId, ItemId>,
        targetIndex: DiffIndex<SectionId, ItemId>
    ) throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw StructurePlanError(message) }
        }
        func contains(_ location: ItemLocation,
                      in sections: [SectionStructure<SectionId, ItemId>]) -> Bool {
            sections.indices.contains(location.section) && sections[location.section].items.indices
                .contains(location.item)
        }
        try require(deletedSections == IndexSet(source.indices.filter {
            targetIndex.sectionIndices[source[$0].id] == nil
        }), "Section deletions must contain exactly the removed identities")
        try require(insertedSections == IndexSet(target.indices.filter {
            sourceIndex.sectionIndices[target[$0].id] == nil
        }), "Section insertions must contain exactly the new identities")
        let removedItems = Set(sourceIndex.itemLocations.compactMap { id, location in
            targetIndex.itemLocations[id] == nil ? location : nil
        })
        let addedItems = Set(targetIndex.itemLocations.compactMap { id, location in
            sourceIndex.itemLocations[id] == nil ? location : nil
        })
        try require(Set(deletedItems) == removedItems && deletedItems.count == removedItems.count,
                    "Item deletions must contain exactly the removed identities")
        try require(Set(insertedItems) == addedItems && insertedItems.count == addedItems.count,
                    "Item insertions must contain exactly the new identities")
        var sectionSources = Set<Int>()
        var sectionDestinations = Set<Int>()
        for move in movedSections {
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
        for move in movedItems {
            try require(
                contains(move.from, in: source) && contains(move.to, in: target),
                "Invalid item move"
            )
            try require(
                source[move.from.section].items[move.from.item] == target[move.to.section]
                    .items[move.to.item],
                "Item move changes identity"
            )
            try require(
                itemSources.insert(move.from).inserted && itemDestinations.insert(move.to).inserted,
                "Conflicting item moves"
            )
        }
        for section in updatedSections {
            try require(target.indices.contains(section), "Invalid section update")
            try require(
                sourceIndex.sectionIndices[target[section].id] != nil,
                "Updated section is not retained"
            )
        }
        var updates = Set<ItemLocation>()
        for item in updatedItems {
            try require(
                contains(item, in: target) && updates.insert(item).inserted,
                "Invalid or repeated item update"
            )
            try require(
                sourceIndex.itemLocations[target[item.section].items[item.item]] != nil,
                "Updated item is not retained"
            )
        }
    }
}
