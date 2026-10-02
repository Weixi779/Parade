//
//  Created by weixi on 2026/9/17.
//

import UIKit

/// One section's captured display version, including its identity and content.
/// Queued updates and data sources use snapshots instead of rereading a mutable controller.
/// Structural batches can derive intermediate snapshots while retaining layout identity.
public struct SectionSnapshot<Layout>: DiffableSection {
    public let id: AnyHashable
    public let cells: [AnyCellPresenter]
    public let supplementaryViews: [AnySupplementaryPresenter]
    let layout: SectionLayoutSnapshot<Layout>

    public var layoutValue: Layout {
        layout.value
    }

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
    init<S: SectionController<Layout>>(capturing section: S) {
        let content = section.captureContent()
        id = AnyHashable(section.id)
        cells = content.cells
        supplementaryViews = content.supplementaryViews
        layout = SectionLayoutSnapshot<Layout>(content.layout)
    }

    public init(
        id: AnyHashable,
        cells: [AnyCellPresenter] = [],
        supplementaryViews: [AnySupplementaryPresenter] = [],
        layout: Layout
    ) {
        self.id = id
        self.cells = cells
        self.supplementaryViews = supplementaryViews
        self.layout = SectionLayoutSnapshot<Layout>(layout)
    }

    private init(
        id: AnyHashable, cells: [AnyCellPresenter],
        supplementaryViews: [AnySupplementaryPresenter], layout: SectionLayoutSnapshot<Layout>
    ) {
        self.id = id
        self.cells = cells
        self.supplementaryViews = supplementaryViews
        self.layout = layout
    }

    public func replacingCells(_ cells: [AnyCellPresenter]) -> Self {
        Self(id: id, cells: cells, supplementaryViews: supplementaryViews, layout: layout)
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
