// Created by weixi on 2026/10/03.

import UIKit

/// Fixed view operations for one collection. Supplied once to the data-source factory.
/// Retain this with that data source; registration, bindings and display lifecycle
/// remain owned by the orchestrator. Operations read the data source's current stage.
@MainActor
public final class CollectionViews {
    private let collectionView: UICollectionView
    private let bridge: CollectionViewBridge

    init(collectionView: UICollectionView, bridge: CollectionViewBridge) {
        self.collectionView = collectionView
        self.bridge = bridge
    }

    /// Use only when UIKit requests a cell. Pass nil for an unresolved presenter
    /// to use Parade's diagnostic fallback.
    public func cell(at indexPath: IndexPath, presenter: AnyCellPresenter?) -> UICollectionViewCell {
        bridge.cell(in: collectionView, at: indexPath, presenter: presenter)
    }

    /// Use only when UIKit requests a supplementary view. The kind must match the request.
    public func supplementary(
        ofKind kind: String,
        at indexPath: IndexPath,
        presenter: AnySupplementaryPresenter?
    ) -> UICollectionReusableView {
        bridge.supplementary(in: collectionView, ofKind: kind, at: indexPath, presenter: presenter)
    }

    /// Refreshes retained, compatible supplementary views after target data is installed.
    /// Updates use target coordinates. Check hasCompatibleSupplementaries(with:) first;
    /// changed identities, placements or view types require the data source's reload path.
    /// Offscreen views are not created. The orchestrator refreshes behavior bindings
    /// after the data source's apply returns.
    public func reconfigureSupplementaries(
        _ updates: [(indexPath: IndexPath, presenter: AnySupplementaryPresenter)]
    ) {
        var changed = false
        for update in updates {
            guard let view = collectionView.supplementaryView(
                forElementKind: update.presenter.elementKind,
                at: update.indexPath
            ) else { continue }
            update.presenter.configure(view)
            view.setNeedsLayout()
            changed = true
        }
        if changed { collectionView.collectionViewLayout.invalidateLayout() }
    }
}
