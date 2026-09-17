//
//  PresenterTests.swift
//  ParadeTests
//
//  Created by weixi on 2026/9/17.
//

import Testing
import UIKit
@testable import Parade

@MainActor
@Suite("Typed presenters")
struct PresenterTests {
    @Test("Content equality is independent of occurrence identity and registration")
    func contentIdentityAndRegistration() {
        let first = AnyCellPresenter(TextPresenter(id: "first", text: "Hello"))
        let second = AnyCellPresenter(TextPresenter(id: "second", text: "Hello"))
        let changed = AnyCellPresenter(TextPresenter(id: "first", text: "Updated"))
        let otherView = AnyCellPresenter(AlternatePresenter(id: "first", text: "Hello"))

        #expect(first.id != second.id)
        #expect(first == second)
        #expect(first.id == changed.id)
        #expect(first != changed)
        #expect(first.registrationKey == changed.registrationKey)
        #expect(first.registrationKey != otherView.registrationKey)
        #expect(first != otherView)
    }

    @Test("An unchanged visual value can replace behavior without reconfiguration")
    func behaviorOnlyUpdate() {
        let cell = TextCell(frame: .zero)
        var received: [String] = []
        let first = AnyCellPresenter(TextPresenter(
            id: "a",
            text: "Hello",
            onTap: { received.append("first") }
        ))
        let next = AnyCellPresenter(TextPresenter(
            id: "a",
            text: "Hello",
            onTap: { received.append("next") }
        ))

        first.configure(cell)
        first.setBehaviors(cell)
        cell.onTap?()
        #expect(first == next)
        next.setBehaviors(cell)
        cell.onTap?()

        #expect(received == ["first", "next"])
        #expect(cell.configureCount == 1)
    }

    @Test("Typed dispatch reaches the correct cell and ignores incompatible instances")
    func typedDispatch() {
        let cell = TextCell(frame: .zero)
        let incompatible = UICollectionViewCell(frame: .zero)
        var events: [String] = []
        let erased = AnyCellPresenter(TextPresenter(
            id: "a",
            text: "Hello",
            onEvent: { events.append($0) }
        ))

        erased.configure(cell)
        #expect(dispatchCapabilities(of: erased, to: cell) != nil)

        erased.configure(incompatible)
        erased.setBehaviors(incompatible)
        #expect(dispatchCapabilities(of: erased, to: incompatible) == nil)
        #expect(cell.text == "Hello")
        #expect(events == [
            "select",
            "deselect",
            "highlight",
            "unhighlight",
            "display",
            "end",
            "menu"
        ])
        #expect(erased.shouldSelect)
        #expect(!erased.shouldDeselect)
        #expect(erased.shouldHighlight)
    }

    @Test("Same-named methods do not opt a core presenter into capabilities")
    func capabilitiesRequireConformance() {
        var events: [String] = []
        let erased = erase(UnclaimedCapabilitiesPresenter(onEvent: { events.append($0) }))
        let cell = TextCell(frame: .zero)

        #expect(dispatchCapabilities(of: erased, to: cell) == nil)
        #expect(erased.shouldSelect)
        #expect(erased.shouldDeselect)
        #expect(erased.shouldHighlight)
        #expect(events.isEmpty)
    }

    @Test(
        "Each capability survives a core-only generic erasure independently",
        arguments: Capability.allCases
    )
    func independentCapabilities(_ capability: Capability) {
        var events: [String] = []
        let onEvent: @MainActor (String) -> Void = { events.append($0) }
        let erased: AnyCellPresenter
        switch capability {
        case .selection: erased = erase(SelectionOnlyPresenter(onEvent: onEvent))
        case .highlight: erased = erase(HighlightOnlyPresenter(onEvent: onEvent))
        case .display: erased = erase(DisplayOnlyPresenter(onEvent: onEvent))
        case .menu: erased = erase(MenuOnlyPresenter(onEvent: onEvent))
        }
        let cell = TextCell(frame: .zero)
        cell.text = "typed"
        let incompatible = UICollectionViewCell(frame: .zero)
        let menu = dispatchCapabilities(of: erased, to: cell, at: CGPoint(x: 12, y: 34))

        #expect(dispatchCapabilities(of: erased, to: incompatible) == nil)
        #expect((menu != nil) == (capability == .menu))
        #expect(events == ["\(capability.rawValue):typed"])
        #expect(erased.shouldSelect == (capability != .selection))
        #expect(erased.shouldDeselect)
        #expect(erased.shouldHighlight == (capability != .highlight))
    }

    @Test("A capability defined only by a consumer survives erasure without library registration")
    func consumerDefinedCapability() throws {
        var received: [String] = []
        let erased = erase(ConsumerPresenter(onAction: { received.append($0) }))
        let handler = try #require(erased.underlyingPresenter as? any ConsumerCellActionHandling)
        let cell = TextCell(frame: .zero)
        cell.text = "consumer action"

        handler.dispatchAction(to: cell)
        handler.dispatchAction(to: UICollectionViewCell(frame: .zero))

        #expect(received == ["consumer action"])
        #expect(erase(OtherTextPresenter(
            id: 1,
            text: "Static"
        )).underlyingPresenter as? any ConsumerCellActionHandling == nil)
    }

    @Test("Optional policies are read by consumers, not during erasure")
    func policyEvaluationTiming() {
        let reads = PolicyReads()
        let erased = erase(PolicyPresenter(reads: reads))
        #expect(reads.counts == [0, 0, 0])

        #expect(!erased.shouldSelect)
        #expect(erased.shouldDeselect)
        #expect(!erased.shouldHighlight)
        #expect(reads.counts == [1, 1, 1])

        #expect(!erased.shouldSelect)
        #expect(reads.counts == [2, 1, 1])
    }

    enum Capability: String, CaseIterable, Sendable {
        case selection, highlight, display, menu
    }

    private func erase<P: CellPresenter>(_ presenter: P) -> AnyCellPresenter {
        AnyCellPresenter(presenter)
    }

    private func dispatchCapabilities(
        of presenter: AnyCellPresenter,
        to cell: UICollectionViewCell,
        at point: CGPoint = .zero
    ) -> UIContextMenuConfiguration? {
        let selection = presenter.underlyingPresenter as? any CellSelectionHandling
        selection?.dispatchSelection(to: cell)
        selection?.dispatchDeselection(to: cell)
        let highlight = presenter.underlyingPresenter as? any CellHighlightHandling
        highlight?.dispatchHighlight(to: cell)
        highlight?.dispatchUnhighlight(to: cell)
        let display = presenter.underlyingPresenter as? any CellDisplayObserving
        display?.dispatchWillDisplay(to: cell)
        display?.dispatchDidEndDisplaying(to: cell)
        let menu = presenter.underlyingPresenter as? any CellContextMenuProviding
        return menu?.dispatchContextMenu(for: cell, at: point)
    }

    @Test("Different presenter types can share a concrete registration")
    func registrationDoesNotCapturePresenterType() {
        let first = AnyCellPresenter(TextPresenter(id: "first", text: "Text"))
        let second = AnyCellPresenter(OtherTextPresenter(id: 2, text: "Other"))
        let cell = TextCell(frame: .zero)

        #expect(first.registrationKey == second.registrationKey)
        #expect(first != second)
        #expect(second != first)
        first.configure(cell)
        #expect(cell.text == "Text")
        second.configure(cell)
        #expect(cell.text == "Other")
    }

    @Test("Prepared registrations retain the cell and configure the newest presenter")
    func preparedRegistrationUsesCurrentPresenter() throws {
        let registry = ViewRegistry()
        let first = AnyCellPresenter(TextPresenter(id: "a", text: "First"))
        let replacement = AnyCellPresenter(OtherTextPresenter(id: 2, text: "Replacement"))
        registry.prepare(first)
        registry.prepare(replacement)

        let source = RegistryDataSource(registry: registry, presenter: first)
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 250, height: 80)
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 200),
            collectionViewLayout: layout
        )
        collectionView.dataSource = source
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        let indexPath = IndexPath(item: 0, section: 0)
        let original = try #require(collectionView.cellForItem(at: indexPath) as? TextCell)
        #expect(original.text == "First")

        source.presenter = replacement
        collectionView.reconfigureItems(at: [indexPath])
        collectionView.layoutIfNeeded()

        let updated = try #require(collectionView.cellForItem(at: indexPath) as? TextCell)
        #expect(updated === original)
        #expect(updated.text == "Replacement")
        // A fresh registration would either replace the cell or trigger UIKit's
        // different-registration reconfiguration exception. Its handler must also
        // accept another presenter type without retaining the original value.
    }

    @Test("Supplementary kind changes registration while item index only changes address")
    func supplementaryAddressAndBehavior() {
        let header = AnySupplementaryPresenter(HeaderPresenter(id: "header", title: "Title"))
        let secondHeader = AnySupplementaryPresenter(HeaderPresenter(
            id: "other",
            title: "Title",
            itemIndex: 1
        ))
        let footer = AnySupplementaryPresenter(HeaderPresenter(
            id: "header",
            title: "Title",
            elementKind: HeaderPresenter.footerKind
        ))
        let view = HeaderView(frame: .zero)
        var result = ""
        let changedBehavior = AnySupplementaryPresenter(HeaderPresenter(
            id: "header",
            title: "Title",
            onTap: { result = "new" }
        ))

        #expect(header.elementKind == UICollectionView.elementKindSectionHeader)
        #expect(header.itemIndex == 0)
        #expect(secondHeader.itemIndex == 1)
        #expect(header.registrationKey == secondHeader.registrationKey)
        #expect(header.registrationKey != footer.registrationKey)
        #expect(header == changedBehavior)
        header.configure(view)
        changedBehavior.setBehaviors(view)
        view.onTap?()
        #expect(view.title == "Title")
        #expect(result == "new")
    }
}

@MainActor
private final class TextCell: UICollectionViewCell {
    var text = ""
    var configureCount = 0
    var onTap: (@MainActor () -> Void)?
}

private struct TextPresenter: CellPresenter,
    CellSelectionHandling,
    CellHighlightHandling,
    CellDisplayObserving,
    CellContextMenuProviding
{
    let id: String
    let text: String
    var onTap: @MainActor () -> Void = {}
    var onEvent: @MainActor (String) -> Void = { _ in }

    var shouldDeselect: Bool { false }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.text == rhs.text }
    func configure(_ cell: TextCell) {
        cell.text = text
        cell.configureCount += 1
    }

    func setBehaviors(_ cell: TextCell) { cell.onTap = onTap }
    func didSelect(_ cell: TextCell) { onEvent("select") }
    func didDeselect(_ cell: TextCell) { onEvent("deselect") }
    func didHighlight(_ cell: TextCell) { onEvent("highlight") }
    func didUnhighlight(_ cell: TextCell) { onEvent("unhighlight") }
    func willDisplay(_ cell: TextCell) { onEvent("display") }
    func didEndDisplaying(_ cell: TextCell) { onEvent("end") }
    func contextMenuConfiguration(
        for cell: TextCell,
        at point: CGPoint
    ) -> UIContextMenuConfiguration? {
        onEvent("menu")
        return UIContextMenuConfiguration(
            identifier: nil,
            previewProvider: nil,
            actionProvider: nil
        )
    }
}

private struct OtherTextPresenter: CellPresenter {
    let id: Int
    let text: String
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.text == rhs.text }
    func configure(_ cell: TextCell) { cell.text = text }
}

// This capability belongs to the test consumer; Parade has no knowledge of it.
private protocol ConsumerCellActionHandling: CellPresenter {
    @MainActor func performAction(_ cell: Cell)
}

@MainActor
private extension ConsumerCellActionHandling {
    func dispatchAction(to rawCell: UICollectionViewCell) {
        guard let cell = rawCell as? Cell else { return }
        performAction(cell)
    }
}

private struct ConsumerPresenter: ConsumerCellActionHandling {
    let id = "consumer"
    let onAction: @MainActor (String) -> Void
    static func == (lhs: Self, rhs: Self) -> Bool { true }
    func configure(_ cell: TextCell) {}
    func performAction(_ cell: TextCell) { onAction(cell.text) }
}

@MainActor
private final class PolicyReads {
    var counts = [0, 0, 0]
}

private struct PolicyPresenter: CellSelectionHandling, CellHighlightHandling {
    let id = "policy"
    let reads: PolicyReads
    var shouldSelect: Bool {
        reads.counts[0] += 1
        return false
    }

    var shouldDeselect: Bool {
        reads.counts[1] += 1
        return true
    }

    var shouldHighlight: Bool {
        reads.counts[2] += 1
        return false
    }

    static func == (lhs: Self, rhs: Self) -> Bool { true }
    func configure(_ cell: TextCell) {}
}

private struct UnclaimedCapabilitiesPresenter: CellPresenter {
    let id = "core"
    let onEvent: @MainActor (String) -> Void
    var shouldSelect: Bool { false }
    var shouldDeselect: Bool { false }
    var shouldHighlight: Bool { false }
    static func == (lhs: Self, rhs: Self) -> Bool { true }
    func configure(_ cell: TextCell) {}
    @MainActor func didSelect(_ cell: TextCell) { onEvent("select") }
    @MainActor func didDeselect(_ cell: TextCell) { onEvent("deselect") }
    @MainActor func didHighlight(_ cell: TextCell) { onEvent("highlight") }
    @MainActor func didUnhighlight(_ cell: TextCell) { onEvent("unhighlight") }
    @MainActor func willDisplay(_ cell: TextCell) { onEvent("display") }
    @MainActor func didEndDisplaying(_ cell: TextCell) { onEvent("end") }
    @MainActor func contextMenuConfiguration(
        for cell: TextCell,
        at point: CGPoint
    ) -> UIContextMenuConfiguration? {
        onEvent("menu")
        return UIContextMenuConfiguration(
            identifier: nil,
            previewProvider: nil,
            actionProvider: nil
        )
    }
}

private struct SelectionOnlyPresenter: CellSelectionHandling {
    let id = "selection"
    let onEvent: @MainActor (String) -> Void
    var shouldSelect: Bool { false }
    static func == (lhs: Self, rhs: Self) -> Bool { true }
    func configure(_ cell: TextCell) {}
    func didSelect(_ cell: TextCell) { onEvent("selection:\(cell.text)") }
}

private struct HighlightOnlyPresenter: CellHighlightHandling {
    let id = "highlight"
    let onEvent: @MainActor (String) -> Void
    var shouldHighlight: Bool { false }
    static func == (lhs: Self, rhs: Self) -> Bool { true }
    func configure(_ cell: TextCell) {}
    func didHighlight(_ cell: TextCell) { onEvent("highlight:\(cell.text)") }
}

private struct DisplayOnlyPresenter: CellDisplayObserving {
    let id = "display"
    let onEvent: @MainActor (String) -> Void
    static func == (lhs: Self, rhs: Self) -> Bool { true }
    func configure(_ cell: TextCell) {}
    func willDisplay(_ cell: TextCell) { onEvent("display:\(cell.text)") }
}

private struct MenuOnlyPresenter: CellContextMenuProviding {
    let id = "menu"
    let onEvent: @MainActor (String) -> Void
    static func == (lhs: Self, rhs: Self) -> Bool { true }
    func configure(_ cell: TextCell) {}
    func contextMenuConfiguration(
        for cell: TextCell,
        at point: CGPoint
    ) -> UIContextMenuConfiguration? {
        #expect(point == CGPoint(x: 12, y: 34))
        onEvent("menu:\(cell.text)")
        return UIContextMenuConfiguration(
            identifier: nil,
            previewProvider: nil,
            actionProvider: nil
        )
    }
}

private struct AlternatePresenter: CellPresenter {
    let id: String
    let text: String
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.text == rhs.text }
    func configure(_ cell: UICollectionViewCell) {}
}

@MainActor
private final class HeaderView: UICollectionReusableView {
    var title = ""
    var onTap: (@MainActor () -> Void)?
}

private struct HeaderPresenter: SupplementaryPresenter {
    let id: String
    let title: String
    let itemIndex: Int
    let elementKind: String
    let onTap: @MainActor () -> Void

    @MainActor
    init(
        id: String,
        title: String,
        itemIndex: Int = 0,
        elementKind: String = UICollectionView.elementKindSectionHeader,
        onTap: @escaping @MainActor () -> Void = {}
    ) {
        self.id = id
        self.title = title
        self.itemIndex = itemIndex
        self.elementKind = elementKind
        self.onTap = onTap
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }
    func configure(_ view: HeaderView) { view.title = title }
    func setBehaviors(_ view: HeaderView) { view.onTap = onTap }
}

@MainActor
private final class RegistryDataSource: NSObject, UICollectionViewDataSource {
    let registry: ViewRegistry
    var presenter: AnyCellPresenter

    init(registry: ViewRegistry, presenter: AnyCellPresenter) {
        self.registry = registry
        self.presenter = presenter
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        1
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        registry.cell(for: presenter, in: collectionView, at: indexPath)
    }
}
