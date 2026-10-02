// Created by weixi on 2026/10/02.

import UIKit

/// Content and layout inputs from one capture. Submitted values and referenced
/// business state must remain stable while retained by Parade.
public protocol SectionContent {
    associatedtype Layout
    var cells: [AnyCellPresenter] { get }
    var supplementaryViews: [AnySupplementaryPresenter] { get }
    @MainActor var layout: Layout { get }
}

public extension SectionContent {
    var supplementaryViews: [AnySupplementaryPresenter] {
        []
    }
}

public struct LayoutContent<Layout>: SectionContent {
    public let cells: [AnyCellPresenter]
    public let supplementaryViews: [AnySupplementaryPresenter]
    public let layout: Layout

    @MainActor
    public init(cells: [AnyCellPresenter], supplementaryViews: [AnySupplementaryPresenter] = [], layout: Layout) {
        self.cells = cells
        self.supplementaryViews = supplementaryViews
        self.layout = layout
    }
}

/// Shared identity of one captured layout across intermediate item stages.
final class SectionLayoutSnapshot<Layout> {
    let value: Layout
    init(_ value: Layout) {
        self.value = value
    }
}

@MainActor
public extension LayoutContent where Layout == CompositionalSectionLayout {
    init(
        cells: [AnyCellPresenter],
        supplementaryViews: [AnySupplementaryPresenter] = [],
        layout: @escaping @MainActor (any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection
    ) {
        self.init(
            cells: cells,
            supplementaryViews: supplementaryViews,
            layout: CompositionalSectionLayout(layout)
        )
    }
}
