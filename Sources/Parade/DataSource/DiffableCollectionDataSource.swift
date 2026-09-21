// Created by weixi on 2026/09/17.

import UIKit

/// Adapts Apple's diffable data source to the same captured presenters and view providers.
/// Native snapshot diffing replaces Parade's sectioned algorithm on this path.
@MainActor
public final class DiffableCollectionDataSource: CollectionDataSource {
    private let collectionView: UICollectionView
    private let cellProvider: CollectionCellProvider
    private let supplementaryProvider: CollectionSupplementaryProvider
    private var current = CollectionComposition.empty
    private var previous = CollectionComposition.empty
    private var sectionIdentifiers = NativeIdentifiers()
    private var itemIdentifiers = NativeIdentifiers()

    // Native IDs are Sendable. Erased presenters and AnyHashable identities stay
    // on MainActor; clients do not need to change their Presenter ID constraints.
    private lazy var native: UICollectionViewDiffableDataSource<Int, Int> = {
        let dataSource = UICollectionViewDiffableDataSource<Int, Int>(collectionView: collectionView) {
            [weak self] collectionView, indexPath, token in
            guard let self else { return nil }
            return cellProvider(collectionView, indexPath, presenter(for: token))
        }
        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            guard let self else { return nil }
            return supplementaryProvider(
                collectionView, kind, indexPath, supplementaryPresenter(ofKind: kind, at: indexPath)
            )
        }
        return dataSource
    }()

    public init(
        collectionView: UICollectionView,
        cellProvider: @escaping CollectionCellProvider,
        supplementaryProvider: @escaping CollectionSupplementaryProvider
    ) {
        self.collectionView = collectionView
        self.cellProvider = cellProvider
        self.supplementaryProvider = supplementaryProvider
    }

    public var dataSource: any UICollectionViewDataSource { native }
    public var sectionIds: [AnyHashable] {
        native.snapshot().sectionIdentifiers.compactMap { sectionIdentifiers.id(for: $0) }
    }
    public var numberOfSections: Int { native.numberOfSections(in: collectionView) }
    public var numberOfItems: Int { native.snapshot().numberOfItems }
    public var isEmpty: Bool {
        numberOfItems == 0 && sectionIds.allSatisfy {
            (current.sectionsById[$0] ?? previous.sectionsById[$0])?.supplementaryViews.isEmpty ?? true
        }
    }

    public func sectionId(at index: Int) -> AnyHashable? {
        guard index >= 0, index < numberOfSections,
              let token = native.sectionIdentifier(for: index) else { return nil }
        return sectionIdentifiers.id(for: token)
    }

    public func sectionIndex(for id: AnyHashable) -> Int? {
        guard let token = sectionIdentifiers.token(for: id) else { return nil }
        return native.index(for: token)
    }

    public func layoutSection(
        at index: Int, environment: any NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection? {
        guard let id = sectionId(at: index) else { return nil }
        return (current.sectionsById[id] ?? previous.sectionsById[id])?.makeLayout(in: environment)
    }

    public func cellPresenter(at indexPath: IndexPath) -> AnyCellPresenter? {
        guard indexPath.section >= 0, indexPath.section < numberOfSections,
              indexPath.item >= 0,
              indexPath.item < native.collectionView(collectionView, numberOfItemsInSection: indexPath.section),
              let token = native.itemIdentifier(for: indexPath) else { return nil }
        return presenter(for: token)
    }

    public func indexPath(for id: AnyHashable) -> IndexPath? {
        guard let token = itemIdentifiers.token(for: id) else { return nil }
        return native.indexPath(for: token)
    }

    public func supplementaryPresenter(ofKind kind: String, at indexPath: IndexPath) -> AnySupplementaryPresenter? {
        guard let id = sectionId(at: indexPath.section),
              let section = current.sectionsById[id] ?? previous.sectionsById[id] else { return nil }
        return section.supplementary(ofKind: kind, at: indexPath.item)
    }

    public func apply(
        from source: CollectionComposition,
        to target: CollectionComposition,
        animated: Bool,
        mode: CollectionUpdateMode
    ) async -> [CollectionDiagnostic] {
        // Resolve old native requests until apply completes. Native snapshot APIs,
        // rather than the target's array offsets, determine current positions.
        previous = source
        current = target
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        for section in target.sections {
            let token = sectionIdentifiers.insert(section.id)
            snapshot.appendSections([token])
            snapshot.appendItems(section.cells.map { itemIdentifiers.insert($0.id) }, toSection: token)
        }

        if mode == .reload || collectionView.window == nil {
            await native.applySnapshotUsingReloadData(snapshot)
        } else {
            let content = CollectionContentUpdates(from: source, to: target)
            snapshot.reloadSections(content.reloadedSections.map {
                sectionIdentifiers.insert(target.sections[$0].id)
            })
            snapshot.reloadItems(content.replacedCells.map {
                itemIdentifiers.insert(target.sections[$0.section].cells[$0.item].id)
            })
            snapshot.reconfigureItems(content.reconfiguredCells.map {
                itemIdentifiers.insert(target.sections[$0.section].cells[$0.item].id)
            })
            await native.apply(snapshot, animatingDifferences: animated)
            content.applySupplementaries(in: collectionView)
        }
        previous = .empty
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.layoutIfNeeded()
        sectionIdentifiers.retain(Set(target.sectionsById.keys))
        itemIdentifiers.retain(Set(target.cellsById.keys))
        return []
    }

    private func presenter(for token: Int) -> AnyCellPresenter? {
        guard let id = itemIdentifiers.id(for: token) else { return nil }
        return current.cellsById[id] ?? previous.cellsById[id]
    }
}

/// A stable native identity for each live logical ID, with both lookup directions.
private struct NativeIdentifiers {
    private var next = 0
    private var tokens: [AnyHashable: Int] = [:]
    private var ids: [Int: AnyHashable] = [:]

    func token(for id: AnyHashable) -> Int? { tokens[id] }
    func id(for token: Int) -> AnyHashable? { ids[token] }

    mutating func insert(_ id: AnyHashable) -> Int {
        if let token = tokens[id] { return token }
        let token = next
        next += 1
        tokens[id] = token
        ids[token] = id
        return token
    }

    mutating func retain(_ live: Set<AnyHashable>) {
        tokens = tokens.filter { live.contains($0.key) }
        ids = ids.filter { live.contains($0.value) }
    }
}
