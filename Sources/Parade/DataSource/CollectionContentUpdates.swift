// Created by weixi on 2026/09/17.

import UIKit

/// A content-update plan shared by manual batches and native snapshots; performs no view operations.
struct CollectionContentUpdates<Layout> {
    var reloadedSections = IndexSet()
    var replacedCells: [IndexPath] = []
    var reconfiguredCells: [IndexPath] = []
    var supplementaryUpdates: [(indexPath: IndexPath, presenter: AnySupplementaryPresenter)] = []
    var hasLayoutUpdates = false

    var isEmpty: Bool {
        reloadedSections.isEmpty && replacedCells.isEmpty && reconfiguredCells.isEmpty && !hasLayoutUpdates
    }

    init(
        from source: CollectionSnapshot<Layout>,
        to target: CollectionSnapshot<Layout>,
        updatedSections: IndexSet? = nil,
        updatedItems: Set<ItemLocation>? = nil
    ) {
        for (sectionIndex, section) in target.sections.enumerated() {
            if let previous = source.sectionsById[section.id] {
                if !previous.hasSameLayoutVersion(as: section) { hasLayoutUpdates = true }
                // A new supplementary topology or view class replaces the section.
                guard previous.hasCompatibleSupplementaries(with: section) else {
                    reloadedSections.insert(sectionIndex)
                    continue
                }
                let sectionChanged = updatedSections?.contains(sectionIndex)
                    ?? !previous.hasSameSupplementaryContent(as: section)
                if sectionChanged {
                    for presenter in section.supplementaryViews {
                        if let old = previous.supplementary(
                            ofKind: presenter.elementKind, at: presenter.itemIndex
                        ), old != presenter {
                            supplementaryUpdates.append((
                                IndexPath(item: presenter.itemIndex, section: sectionIndex), presenter
                            ))
                        }
                    }
                }
            }
            for (itemIndex, presenter) in section.cells.enumerated() {
                guard let previous = source.cellsById[presenter.id] else { continue }
                let path = IndexPath(item: itemIndex, section: sectionIndex)
                if !previous.canReuseView(with: presenter) {
                    replacedCells.append(path)
                } else if updatedItems?.contains(ItemLocation(section: sectionIndex, item: itemIndex))
                    ?? (previous != presenter) {
                    reconfiguredCells.append(path)
                }
            }
        }
    }
}
