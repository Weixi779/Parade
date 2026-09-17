// Created by weixi on 2026/09/17.

import UIKit

/// Owns UIKit's data-source and delegate surface on behalf of the orchestrator.
///
/// Only scroll and flow-layout callbacks are forwarded. Selection, highlighting,
/// display lifecycle, and context menus belong to the submitted presenters.
@MainActor
final class CollectionViewBridge: NSObject,
    UICollectionViewDataSource,
    UICollectionViewDelegateFlowLayout
{
    weak var owner: CollectionOrchestrator?

    private var cells: [ObjectIdentifier: CellRecord] = [:]
    private var supplementaryViews: [ObjectIdentifier: SupplementaryRecord] = [:]
    private var nextGeneration: UInt64 = 0
    private final class EmptyCell: UICollectionViewCell {}
    private static let emptyViewReuseIdentifier = "Parade.CollectionViewBridge.empty"
    private var emptySupplementaryKinds = Set<String>()

    // MARK: - Initialization

    init(owner: CollectionOrchestrator) {
        self.owner = owner
        super.init()
        owner.collectionView.register(
            EmptyCell.self,
            forCellWithReuseIdentifier: Self.emptyViewReuseIdentifier
        )
    }

    // MARK: - Binding Updates

    /// Refreshes closures even when a presenter's visual content compares equal.
    ///
    /// A disappearing view keeps its binding if its identity or registration no
    /// longer matches the current display version. Its end-display callback must
    /// still reach the presenter that actually supplied that view.
    func refreshVisibleBehaviors() {
        guard let owner else { return }
        removeDeallocatedViews()
        let collectionView = owner.collectionView

        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let cell = collectionView.cellForItem(at: indexPath),
                  let record = cells[ObjectIdentifier(cell)],
                  let section = section(at: indexPath.section) else { continue }
            record.refreshBehaviors(in: section, at: indexPath.item)
        }

        // Walk bound views so removed supplementary kinds keep their final callbacks.
        for record in supplementaryViews.values {
            guard let indexPath = visibleIndexPath(for: record, in: collectionView),
                  let section = section(at: indexPath.section) else { continue }
            record.refreshBehaviors(in: section, at: indexPath.item)
        }
    }

    /// Releases all bindings when the orchestrator explicitly detaches.
    /// This does not synthesize display callbacks or business lifecycle events.
    func reset() {
        cells.removeAll()
        supplementaryViews.removeAll()
    }
}

// MARK: - Data Source

extension CollectionViewBridge {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        owner?.displaySections.count ?? 0
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        self.section(at: section)?.cells.count ?? 0
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let owner,
              let section = section(at: indexPath.section),
              let presenter = section.cell(at: indexPath.item) else {
            return dequeueEmptyCell(in: collectionView, at: indexPath)
        }
        let cell = owner.registry.cell(for: presenter, in: collectionView, at: indexPath)
        bind(cell, to: presenter, in: section.id)
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        guard let owner,
              let section = section(at: indexPath.section),
              let presenter = section.supplementary(ofKind: kind, at: indexPath.item) else {
            return dequeueEmptySupplementary(ofKind: kind, in: collectionView, at: indexPath)
        }
        let view = owner.registry.supplementary(for: presenter, in: collectionView, at: indexPath)
        bind(view, to: presenter, in: section.id)
        return view
    }
}

// MARK: - Selection and Interaction

extension CollectionViewBridge {
    func collectionView(
        _ collectionView: UICollectionView,
        shouldSelectItemAt indexPath: IndexPath
    ) -> Bool {
        cellContext(at: indexPath, in: collectionView)?.presenter.shouldSelect ?? false
    }

    func collectionView(
        _ collectionView: UICollectionView,
        shouldDeselectItemAt indexPath: IndexPath
    ) -> Bool {
        cellContext(at: indexPath, in: collectionView)?.presenter.shouldDeselect ?? false
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let context = cellContext(at: indexPath, in: collectionView) else { return }
        let eventHandler = owner?.eventHandler
        if let cell = collectionView.cellForItem(at: indexPath) {
            let handler = context.presenter.underlyingPresenter as? any CellSelectionHandling
            handler?.dispatchSelection(to: cell)
        }
        eventHandler?.didSelect(presenter: context.presenter, in: context.sectionId)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didDeselectItemAt indexPath: IndexPath
    ) {
        guard let context = cellContext(at: indexPath, in: collectionView) else { return }
        let eventHandler = owner?.eventHandler
        if let cell = collectionView.cellForItem(at: indexPath) {
            let handler = context.presenter.underlyingPresenter as? any CellSelectionHandling
            handler?.dispatchDeselection(to: cell)
        }
        eventHandler?.didDeselect(presenter: context.presenter, in: context.sectionId)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        shouldHighlightItemAt indexPath: IndexPath
    ) -> Bool {
        cellContext(at: indexPath, in: collectionView)?.presenter.shouldHighlight ?? false
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didHighlightItemAt indexPath: IndexPath
    ) {
        guard let context = cellContext(at: indexPath, in: collectionView),
              let cell = collectionView.cellForItem(at: indexPath) else { return }
        let handler = context.presenter.underlyingPresenter as? any CellHighlightHandling
        handler?.dispatchHighlight(to: cell)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didUnhighlightItemAt indexPath: IndexPath
    ) {
        guard let context = cellContext(at: indexPath, in: collectionView),
              let cell = collectionView.cellForItem(at: indexPath) else { return }
        let handler = context.presenter.underlyingPresenter as? any CellHighlightHandling
        handler?.dispatchUnhighlight(to: cell)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let context = cellContext(at: indexPath, in: collectionView),
              let cell = collectionView.cellForItem(at: indexPath) else { return nil }
        let provider = context.presenter.underlyingPresenter as? any CellContextMenuProviding
        return provider?.dispatchContextMenu(for: cell, at: point)
    }
}

// MARK: - Display Lifecycle

extension CollectionViewBridge {
    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard let record = cells[ObjectIdentifier(cell)] else { return }
        let binding = record.prepareForDisplay(
            in: section(at: indexPath.section),
            at: indexPath.item
        )
        record.beginDisplay(binding, at: indexPath)
        let observer = binding.presenter.underlyingPresenter as? any CellDisplayObserving
        observer?.dispatchWillDisplay(to: cell)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard let binding = cells[ObjectIdentifier(cell)]?.endDisplay(at: indexPath) else { return }
        let observer = binding.presenter.underlyingPresenter as? any CellDisplayObserving
        observer?.dispatchDidEndDisplaying(to: cell)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplaySupplementaryView view: UICollectionReusableView,
        forElementKind elementKind: String,
        at indexPath: IndexPath
    ) {
        guard let record = supplementaryViews[ObjectIdentifier(view)] else { return }
        let binding = record.prepareForDisplay(
            in: section(at: indexPath.section),
            ofKind: elementKind,
            at: indexPath.item
        )
        record.beginDisplay(binding, at: indexPath)
        let observer = binding.presenter.underlyingPresenter as? any SupplementaryDisplayObserving
        observer?.dispatchWillDisplay(to: view)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplayingSupplementaryView view: UICollectionReusableView,
        forElementOfKind elementKind: String,
        at indexPath: IndexPath
    ) {
        guard let binding = supplementaryViews[ObjectIdentifier(view)]?.endDisplay(
            ofKind: elementKind,
            at: indexPath
        ) else {
            return
        }
        let observer = binding.presenter.underlyingPresenter as? any SupplementaryDisplayObserving
        observer?.dispatchDidEndDisplaying(to: view)
    }
}

// MARK: - UIScrollViewDelegate Forwarding

extension CollectionViewBridge {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        owner?.scrollViewDelegate?.scrollViewDidScroll?(scrollView)
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        owner?.scrollViewDelegate?.scrollViewDidZoom?(scrollView)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        owner?.scrollViewDelegate?.scrollViewWillBeginDragging?(scrollView)
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        owner?.scrollViewDelegate?.scrollViewWillEndDragging?(
            scrollView,
            withVelocity: velocity,
            targetContentOffset: targetContentOffset
        )
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        owner?.scrollViewDelegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
    }

    func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {
        owner?.scrollViewDelegate?.scrollViewWillBeginDecelerating?(scrollView)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        owner?.scrollViewDelegate?.scrollViewDidEndDecelerating?(scrollView)
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        owner?.scrollViewDelegate?.scrollViewDidEndScrollingAnimation?(scrollView)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        owner?.scrollViewDelegate?.viewForZooming?(in: scrollView)
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        owner?.scrollViewDelegate?.scrollViewWillBeginZooming?(scrollView, with: view)
    }

    func scrollViewDidEndZooming(
        _ scrollView: UIScrollView,
        with view: UIView?,
        atScale scale: CGFloat
    ) {
        owner?.scrollViewDelegate?.scrollViewDidEndZooming?(scrollView, with: view, atScale: scale)
    }

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        owner?.scrollViewDelegate?.scrollViewShouldScrollToTop?(scrollView) ?? true
    }

    func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        owner?.scrollViewDelegate?.scrollViewDidScrollToTop?(scrollView)
    }

    func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
        owner?.scrollViewDelegate?.scrollViewDidChangeAdjustedContentInset?(scrollView)
    }
}

// MARK: - UICollectionViewDelegateFlowLayout Forwarding

extension CollectionViewBridge {
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        owner?.flowLayoutDelegate?.collectionView?(
            collectionView,
            layout: collectionViewLayout,
            sizeForItemAt: indexPath
        ) ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize ?? .zero
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        insetForSectionAt section: Int
    ) -> UIEdgeInsets {
        owner?.flowLayoutDelegate?.collectionView?(
            collectionView,
            layout: collectionViewLayout,
            insetForSectionAt: section
        ) ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.sectionInset ?? .zero
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        minimumLineSpacingForSectionAt section: Int
    ) -> CGFloat {
        owner?.flowLayoutDelegate?.collectionView?(
            collectionView,
            layout: collectionViewLayout,
            minimumLineSpacingForSectionAt: section
        ) ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.minimumLineSpacing ?? 0
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        minimumInteritemSpacingForSectionAt section: Int
    ) -> CGFloat {
        owner?.flowLayoutDelegate?.collectionView?(
            collectionView,
            layout: collectionViewLayout,
            minimumInteritemSpacingForSectionAt: section
        ) ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.minimumInteritemSpacing ?? 0
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForHeaderInSection section: Int
    ) -> CGSize {
        owner?.flowLayoutDelegate?.collectionView?(
            collectionView,
            layout: collectionViewLayout,
            referenceSizeForHeaderInSection: section
        ) ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.headerReferenceSize ?? .zero
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForFooterInSection section: Int
    ) -> CGSize {
        owner?.flowLayoutDelegate?.collectionView?(
            collectionView,
            layout: collectionViewLayout,
            referenceSizeForFooterInSection: section
        ) ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.footerReferenceSize ?? .zero
    }
}

// MARK: - Bindings

private extension CollectionViewBridge {
    struct CellBinding {
        let generation: UInt64
        let sectionId: AnyHashable
        let presenter: AnyCellPresenter

        func updating(to presenter: AnyCellPresenter, in sectionId: AnyHashable) -> Self? {
            guard self.presenter.id == presenter.id,
                  self.presenter.registrationKey == presenter.registrationKey else { return nil }
            return Self(generation: generation, sectionId: sectionId, presenter: presenter)
        }
    }

    struct SupplementaryBinding {
        let generation: UInt64
        let sectionId: AnyHashable
        let presenter: AnySupplementaryPresenter

        func updating(to presenter: AnySupplementaryPresenter, in sectionId: AnyHashable) -> Self? {
            guard self.sectionId == sectionId,
                  self.presenter.id == presenter.id,
                  self.presenter.registrationKey == presenter.registrationKey else { return nil }
            return Self(generation: generation, sectionId: sectionId, presenter: presenter)
        }
    }

    struct DisplayBinding<Binding> {
        let indexPath: IndexPath
        var binding: Binding
    }
}

// MARK: - Cell Records

private extension CollectionViewBridge {
    @MainActor
    final class CellRecord {
        private(set) weak var view: UICollectionViewCell?
        private(set) var current: CellBinding
        private var displayed: [DisplayBinding<CellBinding>] = []

        init(view: UICollectionViewCell, binding: CellBinding) {
            self.view = view
            current = binding
        }

        func bind(
            _ presenter: AnyCellPresenter,
            in sectionId: AnyHashable,
            newGeneration: @autoclosure () -> UInt64
        ) {
            // A reconfiguration of the same logical cell retains its display generation.
            if let binding = current.updating(to: presenter, in: sectionId) {
                updateBinding(binding)
            } else {
                current = CellBinding(
                    generation: newGeneration(),
                    sectionId: sectionId,
                    presenter: presenter
                )
            }
        }

        func refreshBehaviors(in section: SectionContent, at item: Int) {
            guard let view,
                  let presenter = section.cell(at: item),
                  let binding = current.updating(to: presenter, in: section.id) else { return }
            updateBinding(binding)
            presenter.setBehaviors(view)
        }

        func prepareForDisplay(in section: SectionContent?, at item: Int) -> CellBinding {
            let previous = current
            guard let view, let section,
                  let presenter = section.cell(at: item),
                  let binding = previous.updating(to: presenter, in: section.id) else {
                return previous
            }
            // Prepared views can reappear without another dequeue or visible refresh.
            let needsConfiguration = previous.presenter != presenter
            updateBinding(binding)
            if needsConfiguration { presenter.configure(view) }
            presenter.setBehaviors(view)
            // Keep this callback's binding even if configuration reenters the bridge.
            return binding
        }

        func beginDisplay(_ binding: CellBinding, at indexPath: IndexPath) {
            displayed.append(DisplayBinding(indexPath: indexPath, binding: binding))
        }

        func endDisplay(at indexPath: IndexPath) -> CellBinding? {
            guard !displayed.isEmpty else { return nil }
            // Preserve the existing fallback: an unmatched path consumes the oldest display.
            let index = displayed.firstIndex { $0.indexPath == indexPath } ?? displayed.startIndex
            // Keep current for prepared-view redisplay; the view itself is held weakly.
            return displayed.remove(at: index).binding
        }

        private func updateBinding(_ binding: CellBinding) {
            current = binding
            for index in displayed.indices
                where displayed[index].binding.generation == binding.generation
            {
                displayed[index].binding = binding
            }
        }
    }
}

// MARK: - Supplementary Records

private extension CollectionViewBridge {
    @MainActor
    final class SupplementaryRecord {
        private(set) weak var view: UICollectionReusableView?
        private(set) var current: SupplementaryBinding
        private var displayed: [DisplayBinding<SupplementaryBinding>] = []

        init(view: UICollectionReusableView, binding: SupplementaryBinding) {
            self.view = view
            current = binding
        }

        func bind(
            _ presenter: AnySupplementaryPresenter,
            in sectionId: AnyHashable,
            newGeneration: @autoclosure () -> UInt64
        ) {
            if let binding = current.updating(to: presenter, in: sectionId) {
                updateBinding(binding)
            } else {
                current = SupplementaryBinding(
                    generation: newGeneration(),
                    sectionId: sectionId,
                    presenter: presenter
                )
            }
        }

        func refreshBehaviors(in section: SectionContent, at item: Int) {
            guard let view,
                  let presenter = section.supplementary(
                      ofKind: current.presenter.elementKind,
                      at: item
                  ),
                  let binding = current.updating(to: presenter, in: section.id) else { return }
            updateBinding(binding)
            presenter.setBehaviors(view)
        }

        func prepareForDisplay(
            in section: SectionContent?,
            ofKind kind: String,
            at item: Int
        ) -> SupplementaryBinding {
            let previous = current
            guard let view, let section,
                  let presenter = section.supplementary(ofKind: kind, at: item),
                  let binding = previous.updating(to: presenter, in: section.id) else {
                return previous
            }
            let needsConfiguration = previous.presenter != presenter
            updateBinding(binding)
            if needsConfiguration { presenter.configure(view) }
            presenter.setBehaviors(view)
            return binding
        }

        func beginDisplay(_ binding: SupplementaryBinding, at indexPath: IndexPath) {
            displayed.append(DisplayBinding(indexPath: indexPath, binding: binding))
        }

        func endDisplay(ofKind kind: String, at indexPath: IndexPath) -> SupplementaryBinding? {
            guard !displayed.isEmpty else { return nil }
            // Preserve the same oldest-display fallback as cells, including kind mismatches.
            let index = displayed.firstIndex {
                $0.indexPath == indexPath && $0.binding.presenter.elementKind == kind
            } ?? displayed.startIndex
            return displayed.remove(at: index).binding
        }

        private func updateBinding(_ binding: SupplementaryBinding) {
            current = binding
            for index in displayed.indices
                where displayed[index].binding.generation == binding.generation
            {
                displayed[index].binding = binding
            }
        }
    }
}

// MARK: - View Binding and Lookup

private extension CollectionViewBridge {
    func bind(
        _ cell: UICollectionViewCell,
        to presenter: AnyCellPresenter,
        in sectionId: AnyHashable
    ) {
        let key = ObjectIdentifier(cell)
        if let record = cells[key], record.view === cell {
            record.bind(presenter, in: sectionId, newGeneration: generation())
            return
        }
        let binding = CellBinding(
            generation: generation(),
            sectionId: sectionId,
            presenter: presenter
        )
        cells[key] = CellRecord(view: cell, binding: binding)
    }

    func bind(
        _ view: UICollectionReusableView,
        to presenter: AnySupplementaryPresenter,
        in sectionId: AnyHashable
    ) {
        let key = ObjectIdentifier(view)
        if let record = supplementaryViews[key], record.view === view {
            record.bind(presenter, in: sectionId, newGeneration: generation())
            return
        }
        let binding = SupplementaryBinding(
            generation: generation(),
            sectionId: sectionId,
            presenter: presenter
        )
        supplementaryViews[key] = SupplementaryRecord(view: view, binding: binding)
    }

    func section(at index: Int) -> SectionContent? {
        guard let owner, owner.displaySections.indices.contains(index) else { return nil }
        return owner.displaySections[index]
    }

    func cellContext(
        at indexPath: IndexPath,
        in collectionView: UICollectionView
    ) -> (presenter: AnyCellPresenter, sectionId: AnyHashable)? {
        if let cell = collectionView.cellForItem(at: indexPath) {
            // A fallback view must not inherit actions from a later presenter at the same path.
            if cell is EmptyCell { return nil }
            if let binding = cells[ObjectIdentifier(cell)]?.current {
                return (binding.presenter, binding.sectionId)
            }
        }
        guard let section = section(at: indexPath.section),
              let presenter = section.cell(at: indexPath.item) else { return nil }
        return (presenter, section.id)
    }

    func visibleIndexPath(
        for record: SupplementaryRecord,
        in collectionView: UICollectionView
    ) -> IndexPath? {
        guard let view = record.view else { return nil }
        let kind = record.current.presenter.elementKind
        return collectionView.indexPathsForVisibleSupplementaryElements(ofKind: kind).first {
            collectionView.supplementaryView(forElementKind: kind, at: $0) === view
        }
    }

    func generation() -> UInt64 {
        nextGeneration &+= 1
        return nextGeneration
    }

    func removeDeallocatedViews() {
        cells = cells.filter { $0.value.view != nil }
        supplementaryViews = supplementaryViews.filter { $0.value.view != nil }
    }
}

// MARK: - Empty View Recovery

private extension CollectionViewBridge {
    func dequeueEmptyCell(
        in collectionView: UICollectionView,
        at indexPath: IndexPath
    ) -> UICollectionViewCell {
        owner?.report(CollectionDiagnostic(
            reason: .missingCell(section: indexPath.section, item: indexPath.item),
            recovery: .displayedEmptyView
        ))
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: Self.emptyViewReuseIdentifier,
            for: indexPath
        )
        cell.isUserInteractionEnabled = false
        cell.accessibilityElementsHidden = true
        return cell
    }

    func dequeueEmptySupplementary(
        ofKind kind: String,
        in collectionView: UICollectionView,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        owner?.report(CollectionDiagnostic(
            reason: .missingSupplementary(
                kind: kind,
                section: indexPath.section,
                item: indexPath.item
            ),
            recovery: .displayedEmptyView
        ))
        // Class registration also handles kinds absent from the submitted presenters.
        if emptySupplementaryKinds.insert(kind).inserted {
            collectionView.register(
                UICollectionReusableView.self,
                forSupplementaryViewOfKind: kind,
                withReuseIdentifier: Self.emptyViewReuseIdentifier
            )
        }
        let view = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: Self.emptyViewReuseIdentifier,
            for: indexPath
        )
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        return view
    }
}
