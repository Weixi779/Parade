// Created by weixi on 2026/10/02.

import UIKit

/// Connects a native layout and its delegate to one section layout type.
/// Factories run once per collection. Return fresh native objects for each owner;
/// geometry and invalidation behavior remain the native layout's responsibility.
@MainActor
public struct CollectionLayout<Layout> {
    let makeLayout: (LayoutAccess<Layout>) -> UICollectionViewLayout
    let makeDelegate: (LayoutAccess<Layout>) -> CollectionLayoutDelegate

    public init(
        makeLayout: @escaping (LayoutAccess<Layout>) -> UICollectionViewLayout,
        makeDelegate: @escaping (LayoutAccess<Layout>) -> CollectionLayoutDelegate = { _ in CollectionLayoutDelegate() }
    ) {
        self.makeLayout = makeLayout
        self.makeDelegate = makeDelegate
    }
}

@MainActor
public final class LayoutAccess<Layout> {
    weak var owner: CollectionOrchestrator<Layout>?

    /// Queries use the native data source's current stage, which can be an
    /// intermediate snapshot during a multi-stage update. Never substitute the
    /// live SectionController's arrays for this coordinate system.
    public func section(at index: Int) -> SectionSnapshot<Layout>? {
        owner?.source.sectionSnapshot(at: index)
    }

    /// Returns nil for a missing item or a different concrete presenter type.
    public func item<P: CellPresenter>(at indexPath: IndexPath, as _: P.Type) -> P? {
        owner?.cellPresenter(at: indexPath)?.underlyingPresenter as? P
    }

    public func indexPath(for id: some Hashable) -> IndexPath? {
        owner?.indexPath(for: id)
    }
}
