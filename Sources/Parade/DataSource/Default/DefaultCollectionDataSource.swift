// Created by weixi on 2026/09/17.

import UIKit

/// Parade's default data source: replaceable sectioned diff and validated UIKit batches.
@MainActor
public final class DefaultCollectionDataSource: NSObject, CollectionDataSource, UICollectionViewDataSource {
    private let collectionView: UICollectionView
    private let cellProvider: CollectionCellProvider
    private let supplementaryProvider: CollectionSupplementaryProvider
    private let diffAlgorithm: any SectionedDiffAlgorithm
    private var sectionLocations: [AnyHashable: Int] = [:]
    private var cellLocations: [AnyHashable: IndexPath] = [:]

    var sections: [SectionContent] = [] {
        didSet {
            sectionLocations.removeAll(keepingCapacity: true)
            cellLocations.removeAll(keepingCapacity: true)
            for (index, section) in sections.enumerated() {
                sectionLocations[section.id] = index
                for (item, presenter) in section.cells.enumerated() {
                    cellLocations[presenter.id] = IndexPath(item: item, section: index)
                }
            }
        }
    }

    public init(
        collectionView: UICollectionView,
        cellProvider: @escaping CollectionCellProvider,
        supplementaryProvider: @escaping CollectionSupplementaryProvider,
        diffAlgorithm: any SectionedDiffAlgorithm = SectionedDiff()
    ) {
        self.collectionView = collectionView
        self.cellProvider = cellProvider
        self.supplementaryProvider = supplementaryProvider
        self.diffAlgorithm = diffAlgorithm
        super.init()
    }

    public var dataSource: any UICollectionViewDataSource { self }
    public var sectionIds: [AnyHashable] { sections.map(\.id) }
    public var numberOfSections: Int { sections.count }
    public var numberOfItems: Int { cellLocations.count }
    public var isEmpty: Bool { sections.allSatisfy(\.isEmpty) }

    public func sectionId(at index: Int) -> AnyHashable? { section(at: index)?.id }
    public func sectionIndex(for id: AnyHashable) -> Int? { sectionLocations[id] }
    public func indexPath(for id: AnyHashable) -> IndexPath? { cellLocations[id] }

    public func cellPresenter(at indexPath: IndexPath) -> AnyCellPresenter? {
        section(at: indexPath.section)?.cell(at: indexPath.item)
    }

    public func supplementaryPresenter(ofKind kind: String, at indexPath: IndexPath) -> AnySupplementaryPresenter? {
        section(at: indexPath.section)?.supplementary(ofKind: kind, at: indexPath.item)
    }

    public func apply(
        from source: CollectionComposition,
        to target: CollectionComposition,
        animated: Bool,
        mode: CollectionUpdateMode
    ) async -> [CollectionDiagnostic] {
        guard mode == .diff, collectionView.window != nil else {
            reload(target)
            return []
        }
        // UIKit must consume the previous counts before the first batch.
        collectionView.layoutIfNeeded()
        let plan: CollectionUpdatePlan
        do {
            plan = try CollectionUpdatePlan(from: source, to: target, using: diffAlgorithm)
        } catch {
            // Planning completes before mutating UIKit, so recovery installs target directly.
            reload(target)
            return [CollectionDiagnostic(
                reason: .invalidDiff(String(describing: error)),
                recovery: .reloadedTarget
            )]
        }

        for batch in plan.batches {
            await performBatch(animated: animated) {
                self.sections = batch.sections
                if !batch.deletedSections.isEmpty {
                    self.collectionView.deleteSections(batch.deletedSections)
                }
                if !batch.insertedSections.isEmpty {
                    self.collectionView.insertSections(batch.insertedSections)
                }
                for move in batch.movedSections {
                    self.collectionView.moveSection(move.from, toSection: move.to)
                }
                if !batch.deletedItems.isEmpty {
                    self.collectionView.deleteItems(at: batch.deletedItems.map(\.indexPath))
                }
                if !batch.insertedItems.isEmpty {
                    self.collectionView.insertItems(at: batch.insertedItems.map(\.indexPath))
                }
                for move in batch.movedItems {
                    self.collectionView.moveItem(at: move.from.indexPath, to: move.to.indexPath)
                }
            }
        }

        let content = plan.content
        if !content.isEmpty {
            await performBatch(animated: animated) {
                self.sections = target.sections
                if !content.reloadedSections.isEmpty {
                    self.collectionView.reloadSections(content.reloadedSections)
                }
                if !content.replacedCells.isEmpty {
                    self.collectionView.reloadItems(at: content.replacedCells)
                }
                if !content.reconfiguredCells.isEmpty {
                    self.collectionView.reconfigureItems(at: content.reconfiguredCells)
                }
            }
        } else {
            sections = target.sections
        }
        content.applySupplementaries(in: collectionView)
        return []
    }

    public func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        self.section(at: section)?.cells.count ?? 0
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        cellProvider(collectionView, indexPath, cellPresenter(at: indexPath))
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        supplementaryProvider(collectionView, kind, indexPath, supplementaryPresenter(ofKind: kind, at: indexPath))
    }

    private func section(at index: Int) -> SectionContent? {
        sections.indices.contains(index) ? sections[index] : nil
    }

    private func reload(_ target: CollectionComposition) {
        sections = target.sections
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
    }

    private func performBatch(animated: Bool, updates: @escaping @MainActor () -> Void) async {
        await withCheckedContinuation { continuation in
            let perform = {
                self.collectionView.performBatchUpdates(updates) { _ in continuation.resume() }
            }
            if animated {
                perform()
            } else {
                UIView.performWithoutAnimation(perform)
            }
        }
    }
}

private extension ItemLocation {
    var indexPath: IndexPath { IndexPath(item: item, section: section) }
}
