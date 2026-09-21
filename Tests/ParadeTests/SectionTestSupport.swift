// Created by weixi on 2026/09/21.

import UIKit
@testable import Parade

extension CapturedSection {
    init(id: AnyHashable, cells: [AnyCellPresenter] = [], supplementaryViews: [AnySupplementaryPresenter] = []) {
        let kinds = supplementaryViews.map(\.elementKind)
        self.init(id: id, cells: cells, supplementaryViews: supplementaryViews, layout: {
            testSectionLayout(kinds: kinds, environment: $0)
        })
    }
}

@MainActor
func testSectionLayout(
    kinds: [String] = [],
    environment: any NSCollectionLayoutEnvironment
) -> NSCollectionLayoutSection {
    let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44))
    let item = NSCollectionLayoutItem(layoutSize: size)
    let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
    let section = NSCollectionLayoutSection(group: group)
    section.boundarySupplementaryItems = kinds.map { kind in
        NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44)),
            elementKind: kind,
            alignment: kind == UICollectionView.elementKindSectionFooter ? .bottom : .top
        )
    }
    return section
}

@MainActor
func testPresentation(
    cells: [AnyCellPresenter], supplementaryViews: [AnySupplementaryPresenter] = []
) -> DefaultSectionPresentation {
    DefaultSectionPresentation(cells: cells, supplementaryViews: supplementaryViews) {
        testSectionLayout(kinds: supplementaryViews.map(\.elementKind), environment: $0)
    }
}
