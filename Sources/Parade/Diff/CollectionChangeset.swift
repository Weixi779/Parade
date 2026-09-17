// Created by weixi on 2026/09/17.

import Foundation

/// The complete update plan. Each structural edit is bound to the data that UIKit
/// must read during that batch; content edits use coordinates in `target`.
struct CollectionChangeset {
    let stages: [Stage]
    let target: CollectionComposition
    let content: Content
    let supplementaryUpdates: [SupplementaryUpdate]

    struct Stage {
        let structure: StructureStage<AnyHashable, AnyHashable>
        let sections: [SectionContent]
    }

    struct Content {
        var reloadedSections = IndexSet()
        var replacedCells: [IndexPath] = []
        var reconfiguredCells: [IndexPath] = []

        var isEmpty: Bool {
            reloadedSections.isEmpty && replacedCells.isEmpty && reconfiguredCells.isEmpty
        }
    }

    struct SupplementaryUpdate {
        let indexPath: IndexPath
        let presenter: AnySupplementaryPresenter
    }
}
