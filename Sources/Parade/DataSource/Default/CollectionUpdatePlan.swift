// Created by weixi on 2026/09/17.

/// A complete update, constructed and validated before UIKit receives any edits.
/// Batches retain source content; the final content phase installs the target.
struct CollectionUpdatePlan {
    let batches: [CollectionBatch]
    let content: CollectionContentUpdates

    init(
        from source: CollectionComposition,
        to target: CollectionComposition,
        using algorithm: any SectionedDiffAlgorithm = SectionedDiff()
    ) throws {
        let changes = try algorithm.diff(from: source.sections, to: target.sections)
        let sourcePositions = try CollectionPositions(source.sections, input: .source)
        let targetPositions = try CollectionPositions(target.sections, input: .target)
        try Self.validate(
            changes, from: source.sections, to: target.sections,
            sourcePositions: sourcePositions, targetPositions: targetPositions
        )

        // Retained identities keep their source presenters even when moved into a
        // new section. Construct this once; every batch then carries real contents.
        let destinations = target.sections.map { section in
            let metadata = source.sectionsById[section.id] ?? section
            return metadata.replacingCells(section.cells.map { source.cellsById[$0.id] ?? $0 })
        }
        var batches: [CollectionBatch] = []
        var current = source.sections

        // Create new destinations before moving retained cells into them. Anchor
        // them before the next surviving section to avoid moves for plain inserts.
        if !changes.insertedSections.isEmpty {
            var insertions = [[SectionContent]](repeating: [], count: current.count + 1)
            var anchor = current.count
            for (index, section) in destinations.enumerated().reversed() {
                if let origin = sourcePositions.sectionIndices[section.id] {
                    anchor = origin
                } else if changes.insertedSections.contains(index) {
                    insertions[anchor].append(section.replacingCells(section.cells.filter {
                        sourcePositions.itemLocations[$0.id] == nil
                    }))
                }
            }
            var batch = CollectionBatch(sections: [])
            for position in 0...current.count {
                for section in insertions[position].reversed() {
                    batch.insertedSections.insert(batch.sections.count)
                    batch.sections.append(section)
                }
                if position < current.count { batch.sections.append(current[position]) }
            }
            batches.append(batch)
            current = batch.sections
        }

        let sectionPositions = Dictionary(uniqueKeysWithValues: current.enumerated().map {
            ($0.element.id, $0.offset)
        })
        func origin(_ location: ItemLocation) -> ItemLocation {
            ItemLocation(
                section: sectionPositions[source.sections[location.section].id]!,
                item: location.item
            )
        }
        func destination(_ location: ItemLocation) -> ItemLocation {
            ItemLocation(
                section: sectionPositions[target.sections[location.section].id]!,
                item: location.item
            )
        }

        // Section positions stay stable during cell edits. Cells that disappear
        // together with their section remain until the final section batch.
        let itemContents = current.map { section in
            if let index = targetPositions.sectionIndices[section.id] {
                return destinations[index]
            }
            return section.replacingCells(section.cells.filter {
                targetPositions.itemLocations[$0.id] == nil
            })
        }
        let itemBatch = CollectionBatch(
            sections: itemContents,
            deletedItems: changes.deletedItems.filter {
                !changes.deletedSections.contains($0.section)
            }.map(origin),
            insertedItems: changes.insertedItems.filter {
                !changes.insertedSections.contains($0.section)
            }.map(destination),
            movedItems: changes.movedItems.map { (from: origin($0.from), to: destination($0.to)) }
        )
        if !itemBatch.isEmpty {
            batches.append(itemBatch)
            current = itemContents
        }

        if current.map(\.id) != destinations.map(\.id) || !changes.movedSections.isEmpty {
            var sectionBatch = CollectionBatch(
                sections: destinations,
                deletedSections: .init(changes.deletedSections.map {
                    sectionPositions[source.sections[$0].id]!
                }),
                movedSections: changes.movedSections.map {
                    (from: sectionPositions[source.sections[$0.from].id]!, to: $0.to)
                }
            )
            // Inserted sections may need to move from their temporary position.
            // Retained section moves remain exactly as the algorithm supplied.
            for index in changes.insertedSections {
                sectionBatch.movedSections.append((
                    from: sectionPositions[target.sections[index].id]!, to: index
                ))
            }
            if !sectionBatch.isEmpty { batches.append(sectionBatch) }
        }

        try Self.validate(batches, from: source.sections, to: target.sections)
        self.batches = batches
        content = CollectionContentUpdates(
            from: source, to: target,
            updatedSections: changes.updatedSections, updatedItems: Set(changes.updatedItems)
        )
    }

    struct ValidationError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
