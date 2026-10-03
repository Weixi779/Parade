// Created by weixi on 2026/10/02.

import UIKit

public extension CollectionOrchestrator where Layout == CompositionalSectionLayout {
    /// Uses a custom data source with the compositional layout integration.
    convenience init(
        collectionView: UICollectionView,
        configuration: UICollectionViewCompositionalLayoutConfiguration? = nil,
        makeDataSource: @MainActor (
            UICollectionView,
            CollectionViews
        ) -> any CollectionDataSource<CompositionalSectionLayout>
    ) {
        self.init(
            collectionView: collectionView,
            layout: .compositional(configuration: configuration ?? .init()),
            makeDataSource: makeDataSource
        )
    }
}
