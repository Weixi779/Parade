//
//  Created by weixi on 2026/9/17.
//

import UIKit

/// A captured composition. Reading a mutable section again during an update would
/// let application state change UIKit's counts in the middle of a batch.
public struct CapturedSection: DiffableSection {
    public let id: AnyHashable
    public let cells: [AnyCellPresenter]
    public let supplementaryViews: [AnySupplementaryPresenter]
    let layout: CapturedCompositionalLayout

    /// Resolves the layout of this captured version, including intermediate stages.
    @MainActor
    public func makeLayout(in environment: any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        layout.makeLayout(environment)
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
    init<S: SectionPresenter>(capturing section: S) {
        let presentation = section.capturePresentation()
        id = AnyHashable(section.id)
        cells = presentation.cells
        supplementaryViews = presentation.supplementaryViews
        layout = CapturedCompositionalLayout(presentation)
    }

    public init(
        id: AnyHashable,
        cells: [AnyCellPresenter] = [],
        supplementaryViews: [AnySupplementaryPresenter] = [],
        layout: @escaping @MainActor (any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection
    ) {
        self.id = id
        self.cells = cells
        self.supplementaryViews = supplementaryViews
        self.layout = CapturedCompositionalLayout(makeLayout: layout)
    }

    private init(
        id: AnyHashable, cells: [AnyCellPresenter],
        supplementaryViews: [AnySupplementaryPresenter], layout: CapturedCompositionalLayout
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
