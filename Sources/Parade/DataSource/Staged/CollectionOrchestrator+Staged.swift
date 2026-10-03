// Created by weixi on 2026/10/03.

import UIKit

public extension CollectionOrchestrator {
    /// Uses staged UIKit updates with a replaceable sectioned diff algorithm.
    convenience init(
        collectionView: UICollectionView,
        layout: CollectionLayout<Layout>,
        diffAlgorithm: any SectionedDiffAlgorithm = SectionedDiff()
    ) {
        self.init(collectionView: collectionView, layout: layout) { view, views in
            StagedCollectionDataSource<Layout>(
                collectionView: view,
                views: views,
                diffAlgorithm: diffAlgorithm
            )
        }
    }
}

public extension CollectionOrchestrator where Layout == CompositionalSectionLayout {
    /// Uses compositional layout with Parade's staged data source.
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
}
