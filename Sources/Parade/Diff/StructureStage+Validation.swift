// Created by weixi on 2026/09/17.

import Foundation

/// Checks the complete plan before UIKit receives its first operation. Replaying
/// from source identities also catches a plausible count with incorrect moves.
extension StructureStage {
    static func validate(
        _ stages: [Self],
        from source: [SectionStructure<SectionId, ItemId>],
        to target: [SectionStructure<SectionId, ItemId>]
    ) throws {
        _ = try DiffIndex(source, id: { $0.id }, items: { $0.items }, input: .source)
        _ = try DiffIndex(target, id: { $0.id }, items: { $0.items }, input: .target)
        var current = source
        for (index, stage) in stages.enumerated() {
            do {
                _ = try DiffIndex(
                    stage.sections,
                    id: { $0.id },
                    items: { $0.items },
                    input: .target
                )
                let replayed = try stage.replaying(from: current)
                try require(
                    replayed == stage.sections,
                    "Operations do not produce the declared stage"
                )
                current = replayed
            } catch {
                throw StructurePlanError("Stage \(index): \(error)")
            }
        }
        try require(current == target, "Plan does not reach the target")
    }

    private func replaying(
        from source: [SectionStructure<SectionId, ItemId>]
    ) throws -> [SectionStructure<SectionId, ItemId>] {
        try Self.require(!isEmpty, "Empty stage")
        if !deletedSections.isEmpty || !insertedSections.isEmpty || !movedSections.isEmpty {
            try Self.require(
                deletedItems.isEmpty && insertedItems.isEmpty && movedItems.isEmpty,
                "Section and item operations share a stage"
            )
            let count = source.count - deletedSections.count + insertedSections.count
            try Self.require(count >= 0 && sections.count == count, "Invalid section count")
            var slots = [SectionStructure<SectionId, ItemId>?](repeating: nil, count: count)
            var removed = Set<Int>()
            for origin in deletedSections {
                try Self.require(
                    source.indices.contains(origin) && removed.insert(origin).inserted,
                    "Invalid or repeated section source"
                )
            }
            for destination in insertedSections {
                try Self.require(slots.indices.contains(destination), "Invalid section destination")
                slots[destination] = sections[destination]
            }
            for move in movedSections {
                try Self.require(
                    source.indices.contains(move.from) && slots.indices.contains(move.to),
                    "Invalid section move"
                )
                try Self.require(
                    removed.insert(move.from).inserted && slots[move.to] == nil,
                    "Conflicting section move"
                )
                slots[move.to] = source[move.from]
            }
            var retained = source.indices.filter { !removed.contains($0) }.makeIterator()
            for destination in slots.indices where slots[destination] == nil {
                guard let origin = retained.next() else {
                    throw StructurePlanError("Missing retained section")
                }
                slots[destination] = source[origin]
            }
            try Self.require(retained.next() == nil, "Extra retained section")
            return slots.compactMap { $0 }
        }

        try Self.require(
            source.map(\.id) == sections.map(\.id),
            "Item stage changed section identities"
        )
        var removed = Set<ItemLocation>()
        var destinations = Set<ItemLocation>()
        var slots = sections.map { [ItemId?](repeating: nil, count: $0.items.count) }
        for origin in deletedItems {
            try Self.require(
                Self.contains(origin, in: source) && removed.insert(origin).inserted,
                "Invalid or repeated item source"
            )
        }
        for destination in insertedItems {
            try Self.require(
                Self.contains(destination, in: sections) &&
                    destinations.insert(destination).inserted,
                "Invalid or repeated item destination"
            )
            slots[destination.section][destination.item] =
                sections[destination.section].items[destination.item]
        }
        for move in movedItems {
            try Self.require(
                Self.contains(move.from, in: source) && Self.contains(move.to, in: sections),
                "Invalid item move"
            )
            try Self.require(
                removed.insert(move.from).inserted && destinations.insert(move.to).inserted,
                "Conflicting item move"
            )
            slots[move.to.section][move.to.item] = source[move.from.section].items[move.from.item]
        }
        for section in source.indices {
            var retained = source[section].items.indices.filter {
                !removed.contains(ItemLocation(section: section, item: $0))
            }.makeIterator()
            for item in slots[section].indices where !destinations.contains(ItemLocation(
                section: section,
                item: item
            )) {
                guard let origin = retained.next() else {
                    throw StructurePlanError("Missing retained item")
                }
                slots[section][item] = source[section].items[origin]
            }
            try Self.require(retained.next() == nil, "Extra retained item")
        }
        return source.indices.map { index in
            SectionStructure(id: source[index].id, items: slots[index].compactMap { $0 })
        }
    }

    private static func contains(
        _ location: ItemLocation,
        in sections: [SectionStructure<SectionId, ItemId>]
    ) -> Bool {
        sections.indices.contains(location.section) &&
            sections[location.section].items.indices.contains(location.item)
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw StructurePlanError(message) }
    }
}

struct StructurePlanError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
