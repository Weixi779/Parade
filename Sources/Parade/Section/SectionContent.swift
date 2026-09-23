// Created by weixi on 2026/09/21.

import UIKit

/// The display content produced by a section: cells, supplementary views, and layout inputs.
/// Keep this content stable after capture; layout construction must not read the live owner.
/// Parade combines it with the section's identity to create a SectionSnapshot.
public protocol SectionContent {
    var cells: [AnyCellPresenter] { get }
    var supplementaryViews: [AnySupplementaryPresenter] { get }

    @MainActor
    func makeLayout(in environment: any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection
}

public extension SectionContent {
    var supplementaryViews: [AnySupplementaryPresenter] { [] }
}

/// A convenience container for section content. Custom content types can conform directly.
public struct DefaultSectionContent: SectionContent {
    public let cells: [AnyCellPresenter]
    public let supplementaryViews: [AnySupplementaryPresenter]
    private let layout: @MainActor (any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection

    public init(
        cells: [AnyCellPresenter],
        supplementaryViews: [AnySupplementaryPresenter] = [],
        layout: @escaping @MainActor (any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection
    ) {
        self.cells = cells
        self.supplementaryViews = supplementaryViews
        self.layout = layout
    }

    @MainActor
    public func makeLayout(in environment: any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        layout(environment)
    }
}

/// Identity belongs to a captured layout version, including when structural
/// stages replace its cells. Closures are deliberately not compared for equality.
final class SectionLayoutSnapshot {
    let makeLayout: @MainActor (any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection

    init(makeLayout: @escaping @MainActor (any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection) {
        self.makeLayout = makeLayout
    }

    @MainActor
    init<C: SectionContent>(_ content: C) {
        makeLayout = { content.makeLayout(in: $0) }
    }
}
