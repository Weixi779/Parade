// Created by weixi on 2026/10/02.

import UIKit

/// A concrete return value builder. Section code still creates native layout sections.
public struct CompositionalSectionLayout {
    public let build: @MainActor (NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection

    public init(_ build: @escaping @MainActor (NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection) {
        self.build = build
    }
}

public extension CollectionLayout where Layout == CompositionalSectionLayout {
    static func compositional(configuration: UICollectionViewCompositionalLayoutConfiguration = .init()) -> Self {
        Self(
            makeLayout: { access in
                UICollectionViewCompositionalLayout(
                    sectionProvider: { index, environment in
                        access.section(at: index)?.layoutValue.build(environment)
                    },
                    configuration: configuration
                )
            },
            makeDelegate: { _ in CollectionLayoutDelegate() }
        )
    }
}
