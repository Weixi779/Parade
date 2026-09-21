//
//  Created by weixi on 2026/9/17.
//

import UIKit

/// Coordinates stable section modules and their captured compositional layouts.
///
/// Retain the orchestrator for as long as the collection view is in use. Parade owns
/// layout, data source and delegate. Sections own business state and submit captured
/// presentation versions through their update context.
@MainActor
public final class CollectionOrchestrator {
    public let collectionView: UICollectionView

    public weak var scrollViewDelegate: (any UIScrollViewDelegate)?
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
    private var members: [ObjectIdentifier: Member] = [:]
    private var appliedComposition = CollectionComposition.empty
    private let submissions: AsyncStream<Submission>.Continuation
    private var pendingCount = 0
    private var emptyView: UIView?
    private var previousBackgroundView: UIView?
    private var diagnostics: [CollectionDiagnostic] = []
    private var diagnosticDeliveryScheduled = false

    /// Uses Parade's default data source with a replaceable sectioned diff algorithm.
    public convenience init(
        collectionView: UICollectionView,
        configuration: UICollectionViewCompositionalLayoutConfiguration? = nil,
        diffAlgorithm: any SectionedDiffAlgorithm = SectionedDiff()
    ) {
        self.init(collectionView: collectionView, configuration: configuration) { view, cell, supplementary in
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
        configuration: UICollectionViewCompositionalLayoutConfiguration? = nil,
        makeDataSource: @MainActor (
            UICollectionView,
            @escaping CollectionCellProvider,
            @escaping CollectionSupplementaryProvider
        ) -> any CollectionDataSource
    ) {
        self.collectionView = collectionView
        let (stream, continuation) = AsyncStream<Submission>.makeStream(bufferingPolicy: .unbounded)
        submissions = continuation
        let bridge = CollectionViewBridge(collectionView: collectionView)
        self.bridge = bridge
        let source = makeDataSource(
            collectionView,
            { view, path, presenter in bridge.cell(in: view, at: path, presenter: presenter) },
            { view, kind, path, presenter in
                bridge.supplementary(in: view, ofKind: kind, at: path, presenter: presenter)
            }
        )
        self.source = source
        bridge.owner = self
        collectionView.dataSource = source.dataSource
        collectionView.delegate = bridge
        collectionView.setCollectionViewLayout(UICollectionViewCompositionalLayout(
            sectionProvider: { [weak source] index, environment in
                source?.layoutSection(at: index, environment: environment)
            },
            configuration: configuration ?? UICollectionViewCompositionalLayoutConfiguration()
        ), animated: false)
        Task { @MainActor [weak self] in
            for await submission in stream {
                guard let self else {
                    submission.completion(.failure(.updateChannelClosed))
                    continue
                }
                await execute(submission)
            }
        }
    }

    deinit { submissions.finish() }

    /// Changes membership and order. Surviving instances retain their latest
    /// accepted content; instances absent at execution use this call's capture.
    /// Await attachment before calling a newly added section's update().
    public func setSections(
        _ sections: [any SectionPresenter],
        animated: Bool = true,
        mode: CollectionUpdateMode = .diff,
        completion: @escaping @MainActor (Result<Void, CollectionUpdateError>) -> Void = { _ in }
    ) {
        let incoming = sections.map { Member($0) }
        // An earlier queued operation can remove a currently attached instance.
        // Keep a fresh capture for reattachment, even if it appears to survive now.
        let captured = incoming.map { $0.capture() }
        // Membership constraints are unconditional. Captured content is only a
        // fallback: earlier operations may attach or remove any incoming instance.
        // Validate content after execution selects the version it will actually use.
        var ids: [AnyHashable: Int] = [:]
        var contexts = Set<ObjectIdentifier>()
        for (index, member) in incoming.enumerated() {
            if let first = ids.updateValue(index, forKey: member.id) {
                reject(.init(
                    .duplicateSectionId(String(describing: member.id)),
                    locations: [.init(section: first), .init(section: index)]
                ), completion: completion)
                return
            }
            guard contexts.insert(ObjectIdentifier(member.context)).inserted else {
                reject(failure(.sectionAlreadyAttached), completion: completion)
                return
            }
        }
        var accepted: [ObjectIdentifier: Member] = [:]
        submit(Submission(makeTarget: { baseline throws(CollectionComposition.ValidationFailure) in
            var next: [ObjectIdentifier: Member] = [:]
            var contents: [CapturedSection] = []
            for (index, candidate) in incoming.enumerated() {
                if let current = self.members[candidate.identity] {
                    guard current.id == candidate.id, let content = baseline.sectionsById[current.id] else {
                        throw self.failure(.staleSectionInstance(String(describing: candidate.id)))
                    }
                    next[current.identity] = current
                    contents.append(content)
                } else {
                    guard candidate.context.owner == nil else { throw self.failure(.sectionAlreadyAttached) }
                    next[candidate.identity] = candidate
                    contents.append(captured[index])
                }
            }
            let target = try CollectionComposition(contents)
            // Reserve new contexts before UIKit suspends, so another collection
            // cannot attach the same module while this operation is in flight.
            for member in next.values where self.members[member.identity] == nil {
                member.context.owner = member
            }
            accepted = next
            return target
        }, animated: animated, mode: mode, didApply: { [self] in
            for member in self.members.values where accepted[member.identity] !== member {
                member.context.disconnect(from: member)
            }
            self.members = accepted
            for member in accepted.values {
                member.context.submit = { [weak self, weak member] animated, mode in
                    guard let self, let member else { throw CollectionUpdateError.sectionNotAttached }
                    try await self.updateMembers([member], animated: animated, mode: mode)
                }
            }
        }, completion: completion))
    }

    public func setSections(
        _ sections: [any SectionPresenter],
        animated: Bool = true,
        mode: CollectionUpdateMode = .diff
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            setSections(sections, animated: animated, mode: mode) { continuation.resume(with: $0) }
        }
    }

    /// Atomically updates one or more attached modules. Use one operation for a
    /// cell transfer between sections, or any coordinated multi-section change.
    public func update(
        _ sections: [any SectionPresenter],
        animated: Bool = true,
        mode: CollectionUpdateMode = .diff
    ) async throws {
        let selected = try sections.map { section in
            guard let member = members[ObjectIdentifier(section)] else {
                throw CollectionUpdateError.sectionNotAttached
            }
            return member
        }
        try await updateMembers(selected, animated: animated, mode: mode)
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
        let makeTarget: @MainActor (CollectionComposition) throws(CollectionComposition.ValidationFailure) -> CollectionComposition
        let animated: Bool
        let mode: CollectionUpdateMode
        let didApply: @MainActor () -> Void
        let completion: @MainActor (Result<Void, CollectionUpdateError>) -> Void

        init(
            makeTarget: @escaping @MainActor (CollectionComposition) throws(CollectionComposition.ValidationFailure) -> CollectionComposition,
            animated: Bool,
            mode: CollectionUpdateMode,
            didApply: @escaping @MainActor () -> Void = {},
            completion: @escaping @MainActor (Result<Void, CollectionUpdateError>) -> Void
        ) {
            self.makeTarget = makeTarget
            self.animated = animated
            self.mode = mode
            self.didApply = didApply
            self.completion = completion
        }
    }

    /// Local and structural operations build against the last completed version.
    /// Their closures retain captured inputs, never recapture live presentation.
    func enqueue(
        animated: Bool,
        mode: CollectionUpdateMode,
        makeTarget: @escaping @MainActor (CollectionComposition) throws(CollectionComposition.ValidationFailure) -> CollectionComposition,
        didApply: @escaping @MainActor () -> Void = {}
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            submit(Submission(makeTarget: makeTarget, animated: animated, mode: mode, didApply: didApply) { result in
                continuation.resume(with: result)
            })
        }
    }

    private func submit(_ submission: Submission) {
        pendingCount += 1
        isApplying = true
        switch submissions.yield(submission) {
        case .enqueued: break
        case .dropped, .terminated:
            pendingCount -= 1
            isApplying = pendingCount > 0
            submission.completion(.failure(.updateChannelClosed))
        @unknown default:
            pendingCount -= 1
            isApplying = pendingCount > 0
            submission.completion(.failure(.updateChannelClosed))
        }
    }

    private func execute(_ submission: Submission) async {
        do {
            let target = try submission.makeTarget(appliedComposition)
            await apply(target, animated: submission.animated, mode: submission.mode)
            appliedComposition = target
            appliedRevision &+= 1
            submission.didApply()
            refreshEmptyView()
            deliverDiagnostics()
            onDidApply?(self)
            submission.completion(.success(()))
        } catch {
            report(error.diagnostic)
            submission.completion(.failure(error.error))
        }
        pendingCount -= 1
        isApplying = pendingCount > 0
        scheduleDiagnosticDelivery()
    }

    private func apply(_ target: CollectionComposition, animated: Bool, mode: CollectionUpdateMode) async {
        // Native registrations must exist before any data-source callback. Prepare
        // at execution so submissions from configure/display callbacks stay safe.
        for section in target.sections {
            for presenter in section.cells { registry.prepare(presenter) }
            for presenter in section.supplementaryViews { registry.prepare(presenter) }
        }
        let recovered = await source.apply(
            from: appliedComposition,
            to: target,
            animated: animated,
            mode: mode
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
    private func updateMembers(_ selected: [Member], animated: Bool, mode: CollectionUpdateMode) async throws {
        let captured = selected.map { $0.capture() }
        do { try validateLocally(captured) }
        catch {
            report(error.diagnostic)
            throw error.error
        }
        for (index, member) in selected.enumerated() where captured[index].id != member.id {
            throw CollectionUpdateError.staleSectionInstance(String(describing: member.id))
        }
        try await enqueue(animated: animated, mode: mode, makeTarget: { baseline throws(CollectionComposition.ValidationFailure) in
            for member in selected {
                guard self.members[member.identity] === member else {
                    throw self.failure(.staleSectionInstance(String(describing: member.id)))
                }
            }
            let replacements = Dictionary(uniqueKeysWithValues: captured.map { ($0.id, $0) })
            return try CollectionComposition(baseline.sections.map { replacements[$0.id] ?? $0 })
        })
    }

    private func validateLocally(_ contents: [CapturedSection]) throws(CollectionComposition.ValidationFailure) {
        var ids: [AnyHashable: Int] = [:]
        for (index, content) in contents.enumerated() {
            if let first = ids.updateValue(index, forKey: content.id) {
                throw CollectionComposition.ValidationFailure(
                    .duplicateSectionId(String(describing: content.id)),
                    locations: [.init(section: first), .init(section: index)]
                )
            }
            do { _ = try CollectionComposition([content]) }
            catch {
                throw CollectionComposition.ValidationFailure(
                    error.error,
                    locations: error.diagnostic.locations.map { .init(section: index, item: $0.item) }
                )
            }
        }
    }

    private func reject(
        _ failure: CollectionComposition.ValidationFailure,
        completion: @MainActor (Result<Void, CollectionUpdateError>) -> Void
    ) {
        report(failure.diagnostic)
        completion(.failure(failure.error))
    }

    private func failure(_ error: CollectionUpdateError) -> CollectionComposition.ValidationFailure {
        .init(error, locations: [])
    }

    @MainActor
    private final class Member {
        let id: AnyHashable
        let identity: ObjectIdentifier
        let context: SectionUpdateContext
        let section: any SectionPresenter

        init<S: SectionPresenter>(_ section: S) {
            id = AnyHashable(section.id)
            identity = ObjectIdentifier(section)
            context = section.updates
            self.section = section
        }

        func capture() -> CapturedSection { CapturedSection(capturing: section) }
    }
}
