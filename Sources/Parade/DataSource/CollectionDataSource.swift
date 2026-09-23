// Created by weixi on 2026/09/17.

import UIKit

/// Parade's fixed dequeue, configuration and binding operation. Pass nil when
/// the requested presenter cannot be resolved to use the diagnostic fallback.
public typealias CollectionCellProvider = @MainActor (
    UICollectionView, IndexPath, AnyCellPresenter?
) -> UICollectionViewCell

public typealias CollectionSupplementaryProvider = @MainActor (
    UICollectionView, String, IndexPath, AnySupplementaryPresenter?
) -> UICollectionReusableView

/// Owns the current data and its UIKit updates for one collection view.
///
/// Construct an instance using CollectionOrchestrator's makeDataSource closure.
/// Use the supplied providers for views; Parade keeps registration, delegate
/// handling, view bindings and submission ordering. Do not replace the delegate.
/// Start empty and submit updates only through the orchestrator.
@MainActor
public protocol CollectionDataSource: AnyObject {
    /// The stable native object installed as UICollectionView.dataSource.
    var dataSource: any UICollectionViewDataSource { get }

    /// Uses the same captured version and section indexing as the current views.
    func layoutSection(
        at index: Int,
        environment: any NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection?

    /// Queries describe the version currently used by the native data source,
    /// including intermediate stages. They must agree with its counts and views.
    var sectionIds: [AnyHashable] { get }
    var numberOfSections: Int { get }
    var numberOfItems: Int { get }
    /// Header-only sections are not empty.
    var isEmpty: Bool { get }
    func sectionId(at index: Int) -> AnyHashable?
    func sectionIndex(for id: AnyHashable) -> Int?
    func cellPresenter(at indexPath: IndexPath) -> AnyCellPresenter?
    func indexPath(for id: AnyHashable) -> IndexPath?
    func supplementaryPresenter(ofKind kind: String, at indexPath: IndexPath) -> AnySupplementaryPresenter?

    /// Applies a validated target, including content and supplementary changes.
    ///
    /// Calls are serialized. Source is the last completed submission. Return only
    /// after this implementation's UIKit work is complete and queries describe
    /// target. If diffing fails, reload the target and return its diagnostic.
    /// Parade then refreshes behavior bindings and delivers public completion.
    /// Cancellation of the submitting task does not undo an accepted update.
    func apply(
        from source: CollectionSnapshot,
        to target: CollectionSnapshot,
        animated: Bool,
        mode: CollectionUpdateMode
    ) async -> [CollectionDiagnostic]
}

public extension CollectionDataSource {
    var numberOfSections: Int { sectionIds.count }

    func sectionId(at index: Int) -> AnyHashable? {
        let ids = sectionIds
        return ids.indices.contains(index) ? ids[index] : nil
    }

    func sectionIndex(for id: AnyHashable) -> Int? {
        sectionIds.firstIndex(of: id)
    }
}
