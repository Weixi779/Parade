// Created by weixi on 2026/09/17.
// Benchmark-only access to the pinned ListKit module. No production API changes.
import UIKit

@MainActor public final class ResearchAdapter {
    let source: CollectionViewDiffableDataSource<Int, String>
    var target = DiffableDataSourceSnapshot<Int, String>()

    public init(collection: UICollectionView,
                provider: @escaping @MainActor (UICollectionView, IndexPath, String) -> UICollectionViewCell?) {
        source = CollectionViewDiffableDataSource(collectionView: collection, cellProvider: provider)
    }

    public func prepare(sectionIDs: [Int], itemIDs: [[String]], updates: [String]) {
        var value = DiffableDataSourceSnapshot<Int, String>()
        for (id, items) in zip(sectionIDs, itemIDs) {
            value.appendSections([id])
            value.appendItems(items, toSection: id)
        }
        if !updates.isEmpty { value.reconfigureItems(updates) }
        target = value
    }

    public func reset() async { await source.applySnapshotUsingReloadData(target) }
    public func apply(exact: Bool) async { await source.apply(target, animatingDifferences: exact) }
    public func snapshotIDs() -> [[String]] {
        let value = source.snapshot()
        return value.sectionIdentifiers.map { value.itemIdentifiers(inSection: $0) }
    }
    public func snapshotSections() -> [Int] { source.snapshot().sectionIdentifiers }

    public static func flatDiff(_ old: [Int], _ new: [Int]) -> (deletes: [Int], inserts: [Int], moves: [[Int]]) {
        let result = HeckelDiff.diff(old: old, new: new)
        return (result.deletes, result.inserts, result.moves.map { [$0.from, $0.to] })
    }
}
