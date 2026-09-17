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
    public var sectionIds: [AnyHashable] { source.sectionIds }
    public var numberOfSections: Int { source.numberOfSections }
    public var numberOfItems: Int { source.numberOfItems }

    let registry = ViewRegistry()
    private let bridge: CollectionViewBridge
    private let source: any CollectionDataSource
    private var appliedComposition = CollectionComposition.empty
    private var pending: [Submission] = []
    private var emptyView: UIView?
    private var previousBackgroundView: UIView?
    private var diagnostics: [CollectionDiagnostic] = []
    private var diagnosticDeliveryScheduled = false

    /// Uses Parade's default data source with a replaceable sectioned diff algorithm.
    public convenience init(
        collectionView: UICollectionView,
        diffAlgorithm: any SectionedDiffAlgorithm = SectionedDiff()
    ) {
        self.init(collectionView: collectionView) { view, cell, supplementary in
            DefaultCollectionDataSource(
                collectionView: view,
                cellProvider: cell,
                supplementaryProvider: supplementary,
                diffAlgorithm: diffAlgorithm
            )
        }
    }

    /// Creates one data-source implementation with Parade's fixed view providers.
    /// The factory runs once and this orchestrator retains the returned instance;
    /// do not share it with another collection view or start updates in the factory.
    public init(
        collectionView: UICollectionView,
        makeDataSource: @MainActor (
            UICollectionView,
            @escaping CollectionCellProvider,
            @escaping CollectionSupplementaryProvider
        ) -> any CollectionDataSource
    ) {
        self.collectionView = collectionView
        let bridge = CollectionViewBridge(collectionView: collectionView)
        self.bridge = bridge
        source = makeDataSource(
            collectionView,
            { view, path, presenter in bridge.cell(in: view, at: path, presenter: presenter) },
            { view, kind, path, presenter in
                bridge.supplementary(in: view, ofKind: kind, at: path, presenter: presenter)
            }
        )
        bridge.owner = self
        collectionView.dataSource = source.dataSource
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
        source.sectionId(at: index)
    }

    public func sectionIndex<Id: Hashable>(for id: Id) -> Int? {
        source.sectionIndex(for: AnyHashable(id))
    }

    public func cellPresenter(at indexPath: IndexPath) -> AnyCellPresenter? {
        source.cellPresenter(at: indexPath)
    }

    public func cellPresenter<Id: Hashable>(for id: Id) -> AnyCellPresenter? {
        guard let location = indexPath(for: id) else { return nil }
        return cellPresenter(at: location)
    }

    public func indexPath<Id: Hashable>(for id: Id) -> IndexPath? {
        source.indexPath(for: AnyHashable(id))
    }

    /// Use this when the layout's supplementary configuration changes with data.
    /// It resolves the current UIKit stage, including additions/removals during an update.
    public func supplementaryPresenter(
        ofKind kind: String,
        at indexPath: IndexPath
    ) -> AnySupplementaryPresenter? {
        source.supplementaryPresenter(ofKind: kind, at: indexPath)
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
        // Native registrations must exist before any data-source callback. Prepare
        // at execution so submissions from configure/display callbacks stay safe.
        for section in submission.composition.sections {
            for presenter in section.cells { registry.prepare(presenter) }
            for presenter in section.supplementaryViews { registry.prepare(presenter) }
        }
        let recovered = await source.apply(
            from: appliedComposition,
            to: submission.composition,
            animated: submission.animated,
            mode: submission.mode
        )
        bridge.refreshVisibleBehaviors()
        collectionView.layoutIfNeeded()
        for diagnostic in recovered { report(diagnostic) }
        logger?("Applied collection update: \(numberOfSections) sections, \(numberOfItems) cells")
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

    private func refreshEmptyView() {
        let isEmpty = source.isEmpty
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
