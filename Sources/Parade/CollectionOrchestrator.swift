//
//  Created by weixi on 2026/9/17.
//

import UIKit

/// Coordinates stable section modules and their captured section layouts.
///
/// Retain the orchestrator for as long as the collection view is in use. Parade owns
/// layout, data source and delegate. Sections own business state and submit captured
/// presentation versions through their update context.
@MainActor
public final class CollectionOrchestrator<Layout>: CollectionViewBridgeOwner {
    public let collectionView: UICollectionView

    public weak var scrollViewDelegate: (any UIScrollViewDelegate)?
    public weak var eventHandler: (any CollectionEventHandler)?

    /// Called after an entire submission has been applied, including supplementary views.
    /// It is safe to enqueue another update from this callback.
    public var onDidApply: (@MainActor (CollectionOrchestrator<Layout>) -> Void)?
    /// Receives recoverable problems after display state has settled and outside
    /// UIKit data-source callbacks. Submitting another update here is safe.
    public var onDiagnostic: (@MainActor (CollectionDiagnostic) -> Void)?

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

    /// The collection's visibility as reported by the application.
    /// Independent from individual cell display and app activity.
    /// Changes immediately notify attached modules, including during a content update.
    /// Newly attached modules begin displaying after their update settles if visible.
    /// Section display additionally requires a displayed cell or supplementary view.
    public var isVisible = false {
        didSet {
            guard oldValue != isVisible else { return }
            for member in members.values {
                // A callback can change visibility again; use the latest value.
                member.setVisible(isVisible)
            }
        }
    }

    /// Queries describe the data source version currently used by UIKit. While an
    /// update is in progress this can be an intermediate stage, not the next target.
    public var sectionIds: [AnyHashable] { source.sectionIds }
    public var numberOfSections: Int { source.numberOfSections }
    public var numberOfItems: Int { source.numberOfItems }

    let registry = ViewRegistry()
    private let bridge: CollectionViewBridge
    private let layoutDelegate: CollectionLayoutDelegate
    let source: any CollectionDataSource<Layout>
    private var members: [ObjectIdentifier: Member] = [:]
    // View bindings use the destination attachment during an update. Notifications
    // settle after the transaction, so intermediate UIKit stages cannot flicker them.
    private var displayMembers: [AnyHashable: Member] = [:]
    private var isUpdatingDisplay = false
    private var displayedSections = Set<SectionDisplayIdentity>()
    private var appliedSnapshot = CollectionSnapshot<Layout>.empty
    private let submissions: AsyncStream<Submission>.Continuation
    private var pendingCount = 0
    private var emptyView: UIView?
    private var previousBackgroundView: UIView?
    private var diagnostics: [CollectionDiagnostic] = []
    private var diagnosticDeliveryScheduled = false

    public convenience init(
        collectionView: UICollectionView,
        layout: CollectionLayout<Layout>,
        diffAlgorithm: any SectionedDiffAlgorithm = SectionedDiff()
    ) {
        self.init(collectionView: collectionView, layout: layout) { view, cell, supplementary in
            DefaultCollectionDataSource<Layout>(
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
        layout: CollectionLayout<Layout>,
        makeDataSource: @MainActor (
            UICollectionView,
            @escaping CollectionCellProvider,
            @escaping CollectionSupplementaryProvider
        ) -> any CollectionDataSource<Layout>
    ) {
        self.collectionView = collectionView
        let (stream, continuation) = AsyncStream<Submission>.makeStream(bufferingPolicy: .unbounded)
        submissions = continuation
        let access = LayoutAccess<Layout>()
        let bridge = CollectionViewBridge(collectionView: collectionView)
        let layoutDelegate = layout.makeDelegate(access)
        precondition(layoutDelegate.bridge == nil, "Create a layout delegate for each collection")
        self.layoutDelegate = layoutDelegate
        layoutDelegate.bridge = bridge
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
        access.owner = self
        collectionView.dataSource = source.dataSource
        collectionView.delegate = layoutDelegate
        collectionView.setCollectionViewLayout(layout.makeLayout(access), animated: false)
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

    deinit {
        submissions.finish()
        // Swift 6.0 does not isolate deinit. Keep the attachment alive until its
        // MainActor cleanup finishes, so it cannot be reused before didDetach.
        let attached = members
        Task { @MainActor in
            for member in attached.values { member.detach() }
        }
    }

    /// Describes the complete target membership and order without submitting it.
    /// New instances use content captured at apply; survivors keep their latest accepted
    /// content unless selected with updating(_:). Call apply() to perform the change.
    public func compose(_ sections: [any SectionController<Layout>]) -> CollectionUpdate<Layout> {
        CollectionUpdate<Layout>(owner: self, composition: sections)
    }

    /// Describes a content update for attached sections without changing their order.
    /// Attachment is checked at apply, not while constructing the description.
    public func update(_ sections: [any SectionController<Layout>]) -> CollectionUpdate<Layout> {
        CollectionUpdate<Layout>(owner: self).updating(sections)
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
        let makeTarget: @MainActor (CollectionSnapshot<Layout>) throws(CollectionSnapshot<Layout>.ValidationFailure) -> CollectionSnapshot<Layout>
        let animated: Bool
        let mode: CollectionUpdateMode
        let didApply: @MainActor () -> Void
        let completion: @MainActor (Result<Void, CollectionUpdateError>) -> Void

        init(
            makeTarget: @escaping @MainActor (CollectionSnapshot<Layout>) throws(CollectionSnapshot<Layout>.ValidationFailure) -> CollectionSnapshot<Layout>,
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

    /// Both public apply forms and section-owned updates enter this capture boundary.
    func apply(
        composition: [any SectionController<Layout>]?,
        updating sections: [any SectionController<Layout>],
        animated: Bool,
        mode: CollectionUpdateMode,
        completion: @escaping @MainActor (Result<Void, CollectionUpdateError>) -> Void
    ) {
        let incoming = composition?.map { Member($0) }
        let selected: [Member]
        do {
            if let incoming {
                try validateMembership(incoming)
                let candidates = Dictionary(uniqueKeysWithValues: incoming.map { ($0.identity, $0) })
                selected = try sections.map { section throws(CollectionSnapshot<Layout>.ValidationFailure) in
                    guard let member = candidates[ObjectIdentifier(section)] else {
                        throw failure(.sectionNotInComposition(String(describing: section.id)))
                    }
                    return member
                }
            } else {
                selected = try sections.map { section throws(CollectionSnapshot<Layout>.ValidationFailure) in
                    guard let member = members[ObjectIdentifier(section)] else {
                        throw failure(.sectionNotAttached)
                    }
                    return member
                }
            }
        } catch {
            reject(error, completion: completion)
            return
        }

        // Composition captures include a fallback for instances that an earlier queued
        // operation removes. Unselected survivors can still use their accepted content.
        let candidates = incoming ?? selected
        let captured = candidates.map { $0.captureSnapshot() }
        let selectedIdentities = Set(selected.map(\.identity))
        let selectedIndices = candidates.indices.filter { selectedIdentities.contains(candidates[$0].identity) }
        do throws(CollectionSnapshot<Layout>.ValidationFailure) {
            try validateLocally(captured, at: selectedIndices)
            for index in selectedIndices {
                let member = candidates[index]
                guard captured[index].id == member.id else {
                    throw failure(.staleSectionInstance(String(describing: member.id)))
                }
            }
        } catch {
            reject(error, completion: completion)
            return
        }

        var accepted: [ObjectIdentifier: Member]?
        submit(Submission(makeTarget: { baseline throws(CollectionSnapshot<Layout>.ValidationFailure) in
            guard let incoming else {
                for member in selected {
                    guard self.members[member.identity] === member else {
                        throw self.failure(.staleSectionInstance(String(describing: member.id)))
                    }
                }
                let replacements = Dictionary(uniqueKeysWithValues: captured.map { ($0.id, $0) })
                return try CollectionSnapshot<Layout>(baseline.sections.map { replacements[$0.id] ?? $0 })
            }

            var next: [ObjectIdentifier: Member] = [:]
            var contents: [SectionSnapshot<Layout>] = []
            for (candidate, capture) in zip(incoming, captured) {
                if let current = self.members[candidate.identity] {
                    guard current.id == candidate.id, let content = baseline.sectionsById[current.id] else {
                        throw self.failure(.staleSectionInstance(String(describing: candidate.id)))
                    }
                    next[current.identity] = current
                    contents.append(selectedIdentities.contains(candidate.identity) ? capture : content)
                } else {
                    guard candidate.context.owner == nil else { throw self.failure(.sectionAlreadyAttached) }
                    next[candidate.identity] = candidate
                    contents.append(capture)
                }
            }
            let target = try CollectionSnapshot<Layout>(contents)
            // Reserve only after the complete target is valid, before UIKit can suspend.
            for member in next.values where self.members[member.identity] == nil {
                member.context.owner = member
            }
            accepted = next
            self.displayMembers = Dictionary(uniqueKeysWithValues: next.values.map { ($0.id, $0) })
            return target
        }, animated: animated, mode: mode, didApply: { [self] in
            guard let accepted, let incoming else { return }
            acceptMembers(accepted, in: incoming)
        }, completion: completion))
    }

    private func validateMembership(_ incoming: [Member]) throws(CollectionSnapshot<Layout>.ValidationFailure) {
        var ids: [AnyHashable: Int] = [:]
        var contexts = Set<ObjectIdentifier>()
        for (index, member) in incoming.enumerated() {
            if let first = ids.updateValue(index, forKey: member.id) {
                throw .init(
                    .duplicateSectionId(String(describing: member.id)),
                    locations: [.init(section: first), .init(section: index)]
                )
            }
            guard contexts.insert(ObjectIdentifier(member.context)).inserted else {
                throw failure(.sectionAlreadyAttached)
            }
        }
    }

    private func acceptMembers(_ accepted: [ObjectIdentifier: Member], in incoming: [Member]) {
        let removed = members.values.filter { accepted[$0.identity] !== $0 }
        let added = incoming.compactMap { candidate -> Member? in
            guard members[candidate.identity] == nil else { return nil }
            return accepted[candidate.identity]
        }
        members = accepted
        for member in accepted.values {
            member.context.submit = { [weak self, weak member] animated, mode in
                guard let self, let member else { throw CollectionUpdateError.sectionNotAttached }
                try await self.update([member.section]).apply(animated: animated, mode: mode)
            }
        }
        for member in removed { member.detach() }
        for member in added { member.attach() }
        for member in added { member.setVisible(isVisible) }
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
            let target = try submission.makeTarget(appliedSnapshot)
            isUpdatingDisplay = true
            await apply(target, animated: submission.animated, mode: submission.mode)
            appliedSnapshot = target
            appliedRevision &+= 1
            submission.didApply()
            isUpdatingDisplay = false
            synchronizeSectionDisplay()
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

    func sectionDisplayIdentity(for sectionId: AnyHashable?) -> SectionDisplayIdentity? {
        guard let sectionId else { return nil }
        return displayMembers[sectionId]?.displayIdentity
    }

    func synchronizeSectionDisplay() {
        guard !isUpdatingDisplay else { return }
        let previous = displayedSections
        displayedSections = bridge.displayedSectionIdentities()
        for identity in previous.symmetricDifference(displayedSections) {
            guard let member = displayMembers[identity.sectionId],
                  member.displayIdentity === identity else { continue }
            // Reentrant callbacks can change the aggregate. Read its latest value,
            // and visit only changed sections rather than every attached feed item.
            member.setHasDisplayedContent(displayedSections.contains(identity))
        }
    }

    private func apply(_ target: CollectionSnapshot<Layout>, animated: Bool, mode: CollectionUpdateMode) async {
        // Native registrations must exist before any data-source callback. Prepare
        // at execution so submissions from configure/display callbacks stay safe.
        for section in target.sections {
            for presenter in section.cells { registry.prepare(presenter) }
            for presenter in section.supplementaryViews { registry.prepare(presenter) }
        }
        let recovered = await source.apply(
            from: appliedSnapshot,
            to: target,
            animated: animated,
            mode: mode
        )
        bridge.refreshVisibleBehaviors()
        collectionView.layoutIfNeeded()
        for diagnostic in recovered { report(diagnostic) }
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
    private func validateLocally(_ contents: [SectionSnapshot<Layout>], at indices: [Int]) throws(CollectionSnapshot<Layout>.ValidationFailure) {
        var ids: [AnyHashable: Int] = [:]
        for index in indices {
            let content = contents[index]
            if let first = ids.updateValue(index, forKey: content.id) {
                throw CollectionSnapshot<Layout>.ValidationFailure(
                    .duplicateSectionId(String(describing: content.id)),
                    locations: [.init(section: first), .init(section: index)]
                )
            }
            do { _ = try CollectionSnapshot<Layout>([content]) }
            catch {
                throw CollectionSnapshot<Layout>.ValidationFailure(
                    error.error,
                    locations: error.diagnostic.locations.map { .init(section: index, item: $0.item) }
                )
            }
        }
    }

    private func reject(
        _ failure: CollectionSnapshot<Layout>.ValidationFailure,
        completion: @MainActor (Result<Void, CollectionUpdateError>) -> Void
    ) {
        report(failure.diagnostic)
        completion(.failure(failure.error))
    }

    private func failure(_ error: CollectionUpdateError) -> CollectionSnapshot<Layout>.ValidationFailure {
        .init(error, locations: [])
    }

    @MainActor
    private final class Member {
        let id: AnyHashable
        let identity: ObjectIdentifier
        let context: SectionUpdateContext
        let section: any SectionController<Layout>
        let displayIdentity: SectionDisplayIdentity
        private var isAttached = false
        private var isCollectionVisible = false
        private var hasDisplayedContent = false
        private var isCollectionDisplayed = false
        private var isSectionDisplayed = false
        private var isNotifyingDisplay = false

        init<S: SectionController<Layout>>(_ section: S) {
            id = AnyHashable(section.id)
            displayIdentity = SectionDisplayIdentity(sectionId: id)
            identity = ObjectIdentifier(section)
            context = section.updateContext
            self.section = section
        }

        func captureSnapshot() -> SectionSnapshot<Layout> {
            SectionSnapshot<Layout>(capturing: section)
        }

        func attach() {
            (section as? any SectionAttachmentObserving)?.didAttach()
            isAttached = true
        }

        func setVisible(_ isVisible: Bool) {
            guard isAttached else { return }
            isCollectionVisible = isVisible
            synchronizeDisplay()
        }

        func setHasDisplayedContent(_ hasContent: Bool) {
            hasDisplayedContent = hasContent
            synchronizeDisplay()
        }

        func detach() {
            guard isAttached else { return }
            isAttached = false
            context.disconnect(from: self)
            synchronizeDisplay()
            (section as? any SectionAttachmentObserving)?.didDetach()
        }

        private func synchronizeDisplay() {
            guard !isNotifyingDisplay else { return }
            isNotifyingDisplay = true
            defer { isNotifyingDisplay = false }

            // A callback may change the desired state. Finish it before delivering
            // another edge, then reevaluate so each begin/end pair stays balanced.
            while true {
                let collectionShouldDisplay = isAttached && isCollectionVisible
                let sectionShouldDisplay = collectionShouldDisplay && hasDisplayedContent
                if isSectionDisplayed && !sectionShouldDisplay {
                    isSectionDisplayed = false
                    (section as? any SectionDisplayObserving)?.sectionDidEndDisplaying()
                } else if isCollectionDisplayed != collectionShouldDisplay {
                    isCollectionDisplayed = collectionShouldDisplay
                    let observer = section as? any CollectionDisplayObserving
                    if collectionShouldDisplay {
                        observer?.collectionWillDisplay()
                    } else {
                        observer?.collectionDidEndDisplaying()
                    }
                } else if isSectionDisplayed != sectionShouldDisplay {
                    isSectionDisplayed = sectionShouldDisplay
                    (section as? any SectionDisplayObserving)?.sectionWillDisplay()
                } else {
                    return
                }
            }
        }
    }
}
