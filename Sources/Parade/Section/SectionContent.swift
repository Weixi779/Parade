//
//  Created by weixi on 2026/9/17.
//

import UIKit

/// A captured composition. Reading a mutable section again during an update would
/// let application state change UIKit's counts in the middle of a batch.
public struct SectionContent: DiffableSection {
    public let id: AnyHashable
    public let cells: [AnyCellPresenter]
    public let supplementaryViews: [AnySupplementaryPresenter]

    public var items: [AnyCellPresenter] { cells }

    public func isContentEqual(to other: Self) -> Bool {
        guard supplementaryViews.count == other.supplementaryViews.count else { return false }
        return other.supplementaryViews.allSatisfy { presenter in
            guard let previous = supplementary(
                ofKind: presenter.elementKind,
                at: presenter.itemIndex
            ) else {
                return false
            }
            return previous.id == presenter.id && previous == presenter
        }
    }

    public var isEmpty: Bool {
        cells.isEmpty && supplementaryViews.isEmpty
    }

    @MainActor
    init<S: SectionPresenter>(_ section: S) {
        id = AnyHashable(section.id)
        cells = section.cells
        supplementaryViews = section.supplementaryViews
    }

    public init(
        id: AnyHashable,
        cells: [AnyCellPresenter] = [],
        supplementaryViews: [AnySupplementaryPresenter] = []
    ) {
        self.id = id
        self.cells = cells
        self.supplementaryViews = supplementaryViews
    }

    public func replacingCells(_ cells: [AnyCellPresenter]) -> Self {
        Self(id: id, cells: cells, supplementaryViews: supplementaryViews)
    }

    public func cell(at item: Int) -> AnyCellPresenter? {
        guard cells.indices.contains(item) else { return nil }
        return cells[item]
    }

    public func supplementary(ofKind kind: String, at item: Int) -> AnySupplementaryPresenter? {
        supplementaryViews.first { $0.elementKind == kind && $0.itemIndex == item }
    }

    /// Checks placement, identity, and registration; visual content may differ.
    func hasCompatibleSupplementaries(with other: Self) -> Bool {
        guard supplementaryViews.count == other.supplementaryViews.count else { return false }
        return other.supplementaryViews.allSatisfy { presenter in
            guard let previous = supplementary(
                ofKind: presenter.elementKind,
                at: presenter.itemIndex
            ) else {
                return false
            }
            return previous.id == presenter.id && previous.registrationKey ==
                presenter.registrationKey
        }
    }
}
