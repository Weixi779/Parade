// Created by weixi on 2026/09/21.

import UIKit

/// One captured display version. Keep its contents and layout inputs immutable
/// after submission; layout construction must not read the live section owner.
public protocol SectionPresentation {
    var cells: [AnyCellPresenter] { get }
    var supplementaryViews: [AnySupplementaryPresenter] { get }

    @MainActor
    func makeLayout(in environment: any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection
}

public extension SectionPresentation {
    var supplementaryViews: [AnySupplementaryPresenter] { [] }
}

/// A convenience implementation. Custom presentation types can conform directly.
public struct DefaultSectionPresentation: SectionPresentation {
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
final class CapturedCompositionalLayout {
    let makeLayout: @MainActor (any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection

    init(makeLayout: @escaping @MainActor (any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection) {
        self.makeLayout = makeLayout
    }

    @MainActor
    init<P: SectionPresentation>(_ presentation: P) {
        makeLayout = { presentation.makeLayout(in: $0) }
    }
}
