// Created by weixi on 2026/09/17.

import UIKit

/// Binds algorithm results to captured presenters and UIKit update stages.
struct CollectionUpdatePlanner {
    private let algorithm: any SectionedDiffAlgorithm

    init(algorithm: any SectionedDiffAlgorithm = SectionedDiff()) {
        self.algorithm = algorithm
    }

    func changeset(
        from source: CollectionComposition,
        to target: CollectionComposition
    ) throws -> CollectionChangeset {
        let changes = try algorithm.diff(from: source.sections, to: target.sections)
        let structureStages = try StructurePlanner.stages(
            for: changes, from: source.structure, to: target.structure
        )
        // Resolve all stages before UIKit starts. Retained presenters and section
        // metadata keep their source content until the final content phase.
        let stages = try structureStages.map { stage in
            let sections = try stage.sections.map { structure in
                guard let section = source.sectionsById[structure.id] ?? target
                    .sectionsById[structure.id] else {
                    throw StructurePlanError("Missing section presenter for \(structure.id)")
                }
                let cells = try structure.items.map { id in
                    guard let presenter = source.cellsById[id] ?? target.cellsById[id] else {
                        throw StructurePlanError("Missing cell presenter for \(id)")
                    }
                    return presenter
                }
                return section.replacingCells(cells)
            }
            return CollectionChangeset.Stage(structure: stage, sections: sections)
        }
        let updatedItems = Set(changes.updatedItems)

        var content = CollectionChangeset.Content()
        var supplementaryUpdates: [CollectionChangeset.SupplementaryUpdate] = []
        for (sectionIndex, section) in target.sections.enumerated() {
            if let previous = source.sectionsById[section.id] {
                // Topology/registration changes need new supplementary views and
                // supersede every item-level content edit in the same section.
                guard previous.hasCompatibleSupplementaries(with: section) else {
                    content.reloadedSections.insert(sectionIndex)
                    continue
                }
                for presenter in section.supplementaryViews
                    where changes.updatedSections.contains(sectionIndex) {
                    if let old = previous.supplementary(
                        ofKind: presenter.elementKind,
                        at: presenter.itemIndex
                    ), old != presenter {
                        supplementaryUpdates.append(.init(
                            indexPath: IndexPath(item: presenter.itemIndex, section: sectionIndex),
                            presenter: presenter
                        ))
                    }
                }
            }
            // Include retained cells transferred into newly inserted sections.
            for (itemIndex, presenter) in section.cells.enumerated() {
                guard let previous = source.cellsById[presenter.id] else { continue }
                let path = IndexPath(item: itemIndex, section: sectionIndex)
                if previous.registrationKey != presenter.registrationKey {
                    content.replacedCells.append(path)
                } else if updatedItems.contains(ItemLocation(
                    section: sectionIndex,
                    item: itemIndex
                )) {
                    content.reconfiguredCells.append(path)
                }
            }
        }
        return CollectionChangeset(
            stages: stages,
            target: target,
            content: content,
            supplementaryUpdates: supplementaryUpdates
        )
    }
}
