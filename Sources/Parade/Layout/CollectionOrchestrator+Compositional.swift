// Created by weixi on 2026/10/02.

import UIKit

public extension CollectionOrchestrator where Layout == CompositionalSectionLayout {
    /// Uses the native compositional layout integration with Parade's staged data source.
    convenience init(
        collectionView: UICollectionView,
        configuration: UICollectionViewCompositionalLayoutConfiguration? = nil,
        diffAlgorithm: any SectionedDiffAlgorithm = SectionedDiff()
    ) {
        self.init(
            collectionView: collectionView,
            layout: .compositional(configuration: configuration ?? .init()),
            diffAlgorithm: diffAlgorithm
        )
    }

    /// Uses a custom data source with the compositional layout integration.
    convenience init(
        collectionView: UICollectionView,
        configuration: UICollectionViewCompositionalLayoutConfiguration? = nil,
        makeDataSource: @MainActor (
            UICollectionView,
            @escaping CollectionCellProvider,
            @escaping CollectionSupplementaryProvider
        ) -> any CollectionDataSource<CompositionalSectionLayout>
    ) {
        self.init(
            collectionView: collectionView,
            layout: .compositional(configuration: configuration ?? .init()),
            makeDataSource: makeDataSource
        )
    }
}
