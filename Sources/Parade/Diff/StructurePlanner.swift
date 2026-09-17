// Created by weixi on 2026/09/17.

/// Translates original diff coordinates into UIKit-safe stages. It never chooses
/// matches or recalculates moves; those decisions belong to the supplied algorithm.
enum StructurePlanner {
    static func stages<SectionId: Hashable, ItemId: Hashable>(
        for changes: SectionedChanges,
        from source: [SectionStructure<SectionId, ItemId>],
        to target: [SectionStructure<SectionId, ItemId>]
    ) throws -> [StructureStage<SectionId, ItemId>] {
        let sourceIndex = try DiffIndex(source, id: { $0.id }, items: { $0.items }, input: .source)
        let targetIndex = try DiffIndex(target, id: { $0.id }, items: { $0.items }, input: .target)
        try changes.validate(
            from: source,
            to: target,
            sourceIndex: sourceIndex,
            targetIndex: targetIndex
        )
        typealias Section = SectionStructure<SectionId, ItemId>
        typealias Stage = StructureStage<SectionId, ItemId>
        var stages: [Stage] = []
        var current = source

        // Insert destinations before any retained item moves into them. New
        // sections are anchored before the next surviving source section so plain
        // prepends/inserts do not need a later section move.
        if !changes.insertedSections.isEmpty {
            var insertions = [[Section]](repeating: [], count: source.count + 1)
            var anchor = source.count
            for (index, section) in target.enumerated().reversed() {
                if let origin = sourceIndex.sectionIndices[section.id] {
                    anchor = origin
                } else if changes.insertedSections.contains(index) {
                    insertions[anchor].append(Section(
                        id: section.id,
                        items: section.items.filter { sourceIndex.itemLocations[$0] == nil }
                    ))
                }
            }
            var stage = Stage(sections: [])
            for position in 0...source.count {
                for section in insertions[position].reversed() {
                    stage.insertedSections.insert(stage.sections.count)
                    stage.sections.append(section)
                }
                if position < source.count { stage.sections.append(source[position]) }
            }
            stages.append(stage)
            current = stage.sections
        }

        let sectionPositions = Dictionary(uniqueKeysWithValues: current.enumerated().map {
            ($0.element.id, $0.offset)
        })
        func origin(_ location: ItemLocation) -> ItemLocation {
            ItemLocation(
                section: sectionPositions[source[location.section].id]!,
                item: location.item
            )
        }
        func destination(_ location: ItemLocation) -> ItemLocation {
            ItemLocation(
                section: sectionPositions[target[location.section].id]!,
                item: location.item
            )
        }

        // Section coordinates stay fixed throughout item edits. Obsolete items
        // in deleted sections remain until section deletion; new items in inserted
        // sections were already included in the first stage.
        let itemTarget = current.map { section -> Section in
            if let targetPosition = targetIndex.sectionIndices[section.id] {
                return target[targetPosition]
            }
            return Section(id: section.id, items: section.items.filter {
                targetIndex.itemLocations[$0] == nil
            })
        }
        let itemStage = Stage(
            sections: itemTarget,
            deletedItems: changes.deletedItems.filter {
                !changes.deletedSections.contains($0.section)
            }.map(origin),
            insertedItems: changes.insertedItems.filter {
                !changes.insertedSections.contains($0.section)
            }.map(destination),
            movedItems: changes.movedItems.map { (from: origin($0.from), to: destination($0.to)) }
        )
        if !itemStage.isEmpty {
            stages.append(itemStage)
            current = itemTarget
        }

        if current != target || !changes.movedSections.isEmpty {
            var sectionStage = Stage(
                sections: target,
                deletedSections: .init(changes.deletedSections
                    .map { sectionPositions[source[$0].id]! }),
                movedSections: changes.movedSections.map {
                    (from: sectionPositions[source[$0.from].id]!, to: $0.to)
                }
            )
            // A new section's temporary insertion position may differ from its
            // final position when retained sections reorder. Reserve its target
            // slot explicitly; retained section moves remain exactly as supplied.
            for index in changes.insertedSections {
                sectionStage.movedSections.append((
                    from: sectionPositions[target[index].id]!,
                    to: index
                ))
            }
            if !sectionStage.isEmpty { stages.append(sectionStage) }
        }
        try Stage.validate(stages, from: source, to: target)
        return stages
    }
}
