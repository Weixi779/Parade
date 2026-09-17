//
//  Created by weixi on 2026/9/17.
//

import UIKit

/// Coordinates submitted section compositions with an application-owned collection view.
///
/// Retain the orchestrator for as long as the collection view is in use. Parade owns
/// the view's data source and delegate; use the forwarding properties for scroll and
/// flow-layout callbacks. Submit new immutable presenters when application state changes.
@MainActor
public final class CollectionOrchestrator {
    public let collectionView: UICollectionView

    public weak var scrollViewDelegate: (any UIScrollViewDelegate)?
    public weak var flowLayoutDelegate: (any UICollectionViewDelegateFlowLayout)?
    public weak var eventHandler: (any CollectionEventHandler)?

    /// Called after an entire submission has been applied, including supplementary views.
    /// It is safe to enqueue another update from this callback.
    public var onDidApply: (@MainActor (CollectionOrchestrator) -> Void)?
    /// Receives recoverable problems after display state has settled and outside
    /// UIKit data-source callbacks. Submitting another update here is safe.
    public var onDiagnostic: (@MainActor (CollectionDiagnostic) -> Void)?
    public var logger: (@MainActor (String) -> Void)?

    /// Optional whole-collection empty content. Header-only sections are not empty.
    /// This never changes scrolling or refresh-control behavior.
    public var emptyViewProvider: (@MainActor () -> UIView?)? {
        didSet {
            removeEmptyView()
            refreshEmptyView()
        }
    }

    public private(set) var isApplying = false
    public private(set) var appliedRevision: UInt64 = 0

    /// Queries describe the data source version currently used by UIKit. While an
    /// update is in progress this can be an intermediate stage, not the next target.
    public var sectionIds: [AnyHashable] { displaySections.map(\.id) }
    public var numberOfSections: Int { displaySections.count }
    public var numberOfItems: Int { cellLocations.count }

    var displaySections: [SectionContent] = [] {
        didSet { rebuildLocations() }
    }

    let registry = ViewRegistry()
    private lazy var bridge = CollectionViewBridge(owner: self)
    private var appliedComposition = CollectionComposition.empty
    private var sectionLocations: [AnyHashable: Int] = [:]
    private var cellLocations: [AnyHashable: IndexPath] = [:]
    private var pending: [Submission] = []
    private var emptyView: UIView?
    private var previousBackgroundView: UIView?
    private var diagnostics: [CollectionDiagnostic] = []
    private var diagnosticDeliveryScheduled = false
    private let planner: CollectionUpdatePlanner

    /// Replaces complete difference calculation. Parade retains input capture,
    /// validation, UIKit batching, content application and update completion.
    public init(
        collectionView: UICollectionView,
        diffAlgorithm: any SectionedDiffAlgorithm = SectionedDiff()
    ) {
        self.collectionView = collectionView
        planner = CollectionUpdatePlanner(algorithm: diffAlgorithm)
        collectionView.dataSource = bridge
        collectionView.delegate = bridge
    }

    /// Enqueues a complete composition. Accepted updates execute in FIFO order.
    ///
    /// The completion is called once, after all UIKit stages and content/behavior
    /// refreshes. Invalid submissions fail before entering the queue. Completion does
    /// not promise that image requests, scrolling, or application animations finished.
    public func apply(
        _ sections: [any SectionPresenter],
        animated: Bool = true,
        mode: CollectionUpdateMode = .diff,
        completion: @escaping @MainActor (Result<Void, CollectionUpdateError>) -> Void = { _ in }
    ) {
        let composition: CollectionComposition
        do {
            composition = try CollectionComposition(sections.map { SectionContent($0) })
        } catch {
            report(error.diagnostic)
            completion(.failure(error.error))
            return
        }
        pending.append(Submission(
            composition: composition,
            animated: animated,
            mode: mode,
            completion: completion
        ))
        guard !isApplying else { return }
        isApplying = true
        Task { @MainActor in
            await drainUpdates()
        }
    }

    /// Cancellation of the awaiting task does not undo an accepted UIKit update.
    /// The await resumes only when this submission has completed or was rejected.
    public func apply(
        _ sections: [any SectionPresenter],
        animated: Bool = true,
        mode: CollectionUpdateMode = .diff
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            apply(sections, animated: animated, mode: mode) { result in
                continuation.resume(with: result)
            }
        }
    }

    public func sectionId(at index: Int) -> AnyHashable? {
        guard displaySections.indices.contains(index) else { return nil }
        return displaySections[index].id
    }

    public func sectionIndex<Id: Hashable>(for id: Id) -> Int? {
        sectionLocations[AnyHashable(id)]
    }

    public func cellPresenter(at indexPath: IndexPath) -> AnyCellPresenter? {
        guard displaySections.indices.contains(indexPath.section) else { return nil }
        return displaySections[indexPath.section].cell(at: indexPath.item)
    }

    public func cellPresenter<Id: Hashable>(for id: Id) -> AnyCellPresenter? {
        guard let location = indexPath(for: id) else { return nil }
        return cellPresenter(at: location)
    }

    public func indexPath<Id: Hashable>(for id: Id) -> IndexPath? {
        cellLocations[AnyHashable(id)]
    }

    /// Use this when the layout's supplementary configuration changes with data.
    /// It resolves the current UIKit stage, including additions/removals during an update.
    public func supplementaryPresenter(
        ofKind kind: String,
        at indexPath: IndexPath
    ) -> AnySupplementaryPresenter? {
        guard displaySections.indices.contains(indexPath.section) else { return nil }
        return displaySections[indexPath.section].supplementary(ofKind: kind, at: indexPath.item)
    }

    public func deselectAllItems(animated: Bool = true) {
        for path in collectionView.indexPathsForSelectedItems ?? [] {
            collectionView.deselectItem(at: path, animated: animated)
        }
    }

    private struct Submission {
        let composition: CollectionComposition
        let animated: Bool
        let mode: CollectionUpdateMode
        let completion: @MainActor (Result<Void, CollectionUpdateError>) -> Void
    }

    private func drainUpdates() async {
        while !pending.isEmpty {
            let submission = pending.removeFirst()
            await apply(submission)
            appliedComposition = submission.composition
            appliedRevision &+= 1
            refreshEmptyView()
            deliverDiagnostics()
            onDidApply?(self)
            submission.completion(.success(()))
        }
        isApplying = false
        scheduleDiagnosticDelivery()
    }

    private func apply(_ submission: Submission) async {
        let target = submission.composition.sections
        // Registration objects must be created outside UIKit's dequeue callbacks.
        // Do this at execution, since a submission itself may be made reentrantly
        // from configuration or display callbacks for the preceding update.
        for section in target {
            for presenter in section.cells { registry.prepare(presenter) }
            for presenter in section.supplementaryViews { registry.prepare(presenter) }
        }
        guard submission.mode == .diff, collectionView.window != nil else {
            reload(submission.composition)
            return
        }

        // UIKit must have consumed the previous counts before the first batch.
        collectionView.layoutIfNeeded()
        let changeset: CollectionChangeset
        do {
            changeset = try planner.changeset(from: appliedComposition, to: submission.composition)
        } catch {
            // Planning has not touched UIKit. The captured target is valid, so
            // recovery can replace it completely before starting any batch.
            reload(submission.composition)
            report(CollectionDiagnostic(
                reason: .invalidDiff(String(describing: error)),
                recovery: .reloadedTarget
            ))
            return
        }

        for planned in changeset.stages {
            let stage = planned.structure
            await batch(animated: submission.animated) {
                self.displaySections = planned.sections
                if !stage.deletedSections.isEmpty {
                    self.collectionView.deleteSections(stage.deletedSections)
                }
                if !stage.insertedSections.isEmpty {
                    self.collectionView.insertSections(stage.insertedSections)
                }
                for move in stage.movedSections {
                    self.collectionView.moveSection(move.from, toSection: move.to)
                }
                if !stage.deletedItems.isEmpty {
                    self.collectionView.deleteItems(at: stage.deletedItems.map(\.indexPath))
                }
                if !stage.insertedItems.isEmpty {
                    self.collectionView.insertItems(at: stage.insertedItems.map(\.indexPath))
                }
                for move in stage.movedItems {
                    self.collectionView.moveItem(at: move.from.indexPath, to: move.to.indexPath)
                }
            }
        }

        let content = changeset.content
        if !content.isEmpty {
            await batch(animated: submission.animated) {
                self.displaySections = changeset.target.sections
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
            displaySections = changeset.target.sections
        }

        var supplementaryContentChanged = false
        for update in changeset.supplementaryUpdates {
            guard let view = collectionView.supplementaryView(
                forElementKind: update.presenter.elementKind,
                at: update.indexPath
            ) else { continue }
            update.presenter.configure(view)
            view.setNeedsLayout()
            supplementaryContentChanged = true
        }
        bridge.refreshVisibleBehaviors()
        if supplementaryContentChanged { collectionView.collectionViewLayout.invalidateLayout() }
        collectionView.layoutIfNeeded()
        logger?(
            "Applied collection diff: \(changeset.stages.count) structural stages, \(content.reconfiguredCells.count) reconfigurations, \(content.replacedCells.count) replacements"
        )
    }

    private func reload(_ target: CollectionComposition) {
        displaySections = target.sections
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        bridge.refreshVisibleBehaviors()
        logger?(
            "Applied collection reload: \(target.sections.count) sections, \(numberOfItems) cells"
        )
    }

    /// Bridge diagnostics must not call application code from within dequeue.
    func report(_ diagnostic: CollectionDiagnostic) {
        diagnostics.append(diagnostic)
        scheduleDiagnosticDelivery()
    }

    private func scheduleDiagnosticDelivery() {
        guard !diagnostics.isEmpty, !isApplying, !diagnosticDeliveryScheduled else { return }
        diagnosticDeliveryScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            diagnosticDeliveryScheduled = false
            if !isApplying { deliverDiagnostics() }
        }
    }

    private func deliverDiagnostics() {
        let pending = diagnostics
        diagnostics.removeAll()
        for diagnostic in pending {
            logger?("Collection diagnostic: \(diagnostic)")
            onDiagnostic?(diagnostic)
        }
    }

    private func batch(animated: Bool, updates: @escaping @MainActor () -> Void) async {
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

    private func rebuildLocations() {
        sectionLocations.removeAll(keepingCapacity: true)
        cellLocations.removeAll(keepingCapacity: true)
        for (section, value) in displaySections.enumerated() {
            sectionLocations[value.id] = section
            for (item, presenter) in value.cells.enumerated() {
                cellLocations[presenter.id] = IndexPath(item: item, section: section)
            }
        }
    }

    private func refreshEmptyView() {
        let isEmpty = displaySections.allSatisfy(\.isEmpty)
        guard isEmpty, let provider = emptyViewProvider else {
            removeEmptyView()
            return
        }
        guard emptyView == nil, let view = provider() else { return }
        previousBackgroundView = collectionView.backgroundView
        emptyView = view
        collectionView.backgroundView = view
    }

    private func removeEmptyView() {
        if let emptyView, collectionView.backgroundView === emptyView {
            collectionView.backgroundView = previousBackgroundView
        }
        emptyView = nil
        previousBackgroundView = nil
    }
}

private extension ItemLocation {
    var indexPath: IndexPath { IndexPath(item: item, section: section) }
}
