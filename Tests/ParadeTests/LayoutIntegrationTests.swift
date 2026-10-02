// Created by weixi on 2026/10/02.

import Parade
import ParadeLayoutSupport
import Testing
import UIKit

@MainActor @Suite("Typed layout assembly", .serialized)
struct LayoutTests {
    func cards(_ log: EventLog) -> [Card] {
        [Card(1, height: 80, log: log), Card(2, height: 140, log: log), Card(3, height: 100, log: log)]
    }

    @Test("Two concrete section and delegate types assemble without caller existentials", arguments: [false, true])
    func flowAssembly(diffable: Bool) async throws {
        let log = EventLog(), fixture = Fixture(layout: .flow(), diffable: diffable)
        defer { fixture.window.isHidden = true }
        let a = FlowCards(cards: cards(log), log: log), b = FlowBanner(log: log)
        try await fixture.owner.compose([b, a]).apply(animated: false)
        fixture.settle()
        #expect(fixture.owner.numberOfSections == 2)
        #expect(fixture.frame(900)?.height == 64)
        #expect(fixture.frame(2)?.height == 140)
        #expect(fixture.view.collectionViewLayout.layoutAttributesForSupplementaryView(
            ofKind: UICollectionView.elementKindSectionHeader,
            at: IndexPath(item: 0, section: 1)
        )?.frame.height == 32)
        #expect(!log.displayed.isEmpty)
        fixture.view.delegate?.collectionView?(fixture.view, didSelectItemAt: IndexPath(item: 0, section: 1))
        #expect(log.selected == [1])
    }

    @Test("A layout-only update refreshes native flow geometry", arguments: [false, true])
    func flowLayoutOnly(diffable: Bool) async throws {
        let log = EventLog(), fixture = Fixture(layout: .flow(), diffable: diffable)
        defer { fixture.window.isHidden = true }
        let section = FlowCards(cards: cards(log), log: log)
        try await fixture.owner.compose([section]).apply(animated: false)
        section.scale = 1.5
        try await section.update(animated: false)
        fixture.settle()
        #expect(fixture.frame(2)?.height == 210)
        #expect(fixture.owner.appliedRevision == 2)
    }

    @Test("Compose retains captured layout until the section is selected for update", arguments: [false, true])
    func captureBoundary(diffable: Bool) async throws {
        let log = EventLog(), fixture = Fixture(layout: .flow(), diffable: diffable)
        defer { fixture.window.isHidden = true }
        let a = FlowCards(cards: cards(log), log: log), b = FlowBanner(log: log)
        try await fixture.owner.compose([a, b]).apply(animated: false)
        a.scale = 2
        try await fixture.owner.compose([b, a]).apply(animated: false)
        fixture.settle()
        #expect(fixture.frame(1)?.height == 80)
        try await fixture.owner.compose([a, b]).updating([a]).apply(animated: false)
        fixture.settle()
        #expect(fixture.frame(1)?.height == 160)
    }

    @Test("Queued submissions freeze delegate settings before later business mutations", arguments: [false, true])
    func queuedCapture(diffable: Bool) async throws {
        let log = EventLog(), fixture = Fixture(layout: .flow(), diffable: diffable)
        defer { fixture.window.isHidden = true }
        let section = FlowCards(cards: cards(log), log: log)
        try await fixture.owner.compose([section]).apply(animated: false)
        var heights: [CGFloat] = []
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            section.scale = 2
            fixture.owner.update([section]).apply(animated: true) { result in
                if case let .failure(error) = result {
                    Issue.record("First submission: \(error)")
                }
                fixture.settle()
                heights.append(fixture.frame(1)?.height ?? -1)
            }
            section.scale = 3
            fixture.owner.update([section]).apply(animated: false) { result in
                fixture.settle()
                heights.append(fixture.frame(1)?.height ?? -1)
                done.resume(with: result.mapError { $0 as Error })
            }
            section.scale = 99
        }
        #expect(heights == [160, 240])
    }

    @Test(
        "Section reorder, item transfer, insertion and deletion use current datasource coordinates",
        arguments: [false, true]
    )
    func structuralChanges(diffable: Bool) async throws {
        let log = EventLog(), fixture = Fixture(layout: .flow(), diffable: diffable)
        defer { fixture.window.isHidden = true }
        let a = FlowCards(id: "a", cards: cards(log), log: log)
        let b = FlowCards(id: "b", cards: [Card(4, height: 60, log: log)], log: log)
        try await fixture.owner.compose([a, b]).apply(animated: false)
        a.cards = [Card(5, height: 50, log: log), a.cards[2]]
        b.cards = [Card(2, height: 180, log: log), b.cards[0]]
        try await fixture.owner.compose([b, a]).updating([a, b]).apply(animated: true)
        fixture.settle()
        #expect(fixture.owner.indexPath(for: 1) == nil)
        #expect(fixture.owner.indexPath(for: 2) == IndexPath(item: 0, section: 0))
        #expect(fixture.frame(2)?.height == 180)
        #expect(fixture.frame(5)?.height == 50)
        #expect(fixture.view.numberOfItems(inSection: 1) == 2)
    }

    @Test("Native flow defaults still apply when a section omits optional delegate methods", arguments: [false, true])
    func flowDefaults(diffable: Bool) async throws {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 17
        let fixture = Fixture(layout: .flow(layout), diffable: diffable), log = EventLog()
        defer { fixture.window.isHidden = true }
        let a = FlowCards(cards: cards(log), log: log)
        a.columns = 1
        try await fixture.owner.compose([a]).apply(animated: false)
        fixture.settle()
        let one = try #require(fixture.frame(1)), two = try #require(fixture.frame(2))
        #expect(abs(two.minY - one.maxY - 17) < 0.1)
    }

    @Test("Concrete compositional return path preserves capture and update semantics", arguments: [false, true])
    func compositional(diffable: Bool) async throws {
        let log = EventLog(), fixture = Fixture(layout: .compositional(), diffable: diffable)
        defer { fixture.window.isHidden = true }
        let section = CompositionalCards(cards: cards(log))
        try await fixture.owner.compose([section]).apply(animated: false)
        fixture.settle()
        #expect(fixture.frame(1)?.height == 92)
        section.height = 150
        try await section.update(animated: false)
        fixture.settle()
        #expect(fixture.frame(1)?.height == 150)
    }

    @Test("An external custom layout protocol needs no new branch inside Parade", arguments: [false, true])
    func waterfall(diffable: Bool) async throws {
        let log = EventLog(), fixture = Fixture(layout: .waterfall(), diffable: diffable)
        defer { fixture.window.isHidden = true }
        let section = WaterfallCards(cards: cards(log))
        try await fixture.owner.compose([section]).apply(animated: false)
        fixture.settle()
        let one = try #require(fixture.frame(1)), two = try #require(fixture.frame(2)),
            three = try #require(fixture.frame(3))
        #expect(three.minX == one.minX)
        #expect(three.minY == one.maxY + 10)
        #expect(three.minY < two.maxY)
        section.columns = 1
        try await section.update(animated: false)
        fixture.settle()
        #expect(fixture.frame(2)?.minY == 102)
        fixture.view.delegate?.collectionView?(fixture.view, didSelectItemAt: IndexPath(item: 0, section: 0))
        #expect(log.selected == [1])
        #expect(!log.displayed.isEmpty)
    }

    @Test("A typed SectionStore still reuses section instances", arguments: [false, true])
    func store(diffable: Bool) async throws {
        let log = EventLog(), fixture = Fixture(layout: .flow(), diffable: diffable)
        defer { fixture.window.isHidden = true }
        let store = SectionStore<FlowSectionLayout>()
        func definition(_ height: CGFloat) -> SectionDefinition<FlowSectionLayout> {
            SectionDefinition(
                id: "stored",
                input: height,
                make: { FlowCards(id: "stored", cards: [Card(1, height: $0, log: log)], log: log) },
                update: { section, height in section.cards = [Card(1, height: height, log: log)] }
            )
        }
        try await store.reconcile([definition(60)]) { change in
            try await fixture.owner.compose(change.controllers).updating(change.retained).apply(animated: false)
        }
        let first = ObjectIdentifier(store.controllers[0])
        try await store.reconcile([definition(160)]) { change in
            try await fixture.owner.compose(change.controllers).updating(change.retained).apply(animated: false)
        }
        fixture.settle()
        #expect(ObjectIdentifier(store.controllers[0]) == first)
        #expect(fixture.frame(1)?.height == 160)
    }

    @Test(
        "Removing a captured flow section releases its delegate after datasource history retires",
        arguments: [false, true]
    )
    func delegateLifetime(diffable: Bool) async throws {
        let log = EventLog(), fixture = Fixture(layout: .flow(), diffable: diffable)
        defer { fixture.window.isHidden = true }
        let section = FlowCards(cards: cards(log), log: log)
        try await fixture.owner.compose([section]).apply(animated: false)
        fixture.settle()
        #expect(log.lastDelegate != nil)
        try await fixture.owner.compose([]).apply(animated: false)
        try await fixture.owner.compose([]).apply(animated: false)
        #expect(log.lastDelegate == nil)
    }

    @Test("A captured delegate is reused for queries and replaced by the next capture", arguments: [false, true])
    func capturedDelegateReuse(diffable: Bool) async throws {
        let log = EventLog(), fixture = Fixture(layout: .flow(), diffable: diffable)
        defer { fixture.window.isHidden = true }
        let section = FlowCards(cards: cards(log), log: log)
        try await fixture.owner.compose([section]).apply(animated: false)
        fixture.settle()
        #expect(log.factories == 1)
        fixture.view.collectionViewLayout.invalidateLayout()
        fixture.settle()
        #expect(log.factories == 1)
        section.scale = 2
        try await section.update(animated: false)
        fixture.settle()
        #expect(log.factories == 2)
        #expect(fixture.frame(1)?.height == 160)
    }

    @Test("Retaining layout access does not retain its collection owner", arguments: [false, true])
    func retainedAccessAfterOwnerRelease(diffable: Bool) async throws {
        let log = EventLog()
        var fixture: Fixture<FlowSectionLayout>? = Fixture(layout: .flow(), diffable: diffable)
        let section = FlowCards(cards: cards(log), log: log)
        try await fixture?.owner.compose([section]).apply(animated: false)
        fixture?.settle()
        let access = try #require(log.lastAccess)
        weak var owner = fixture?.owner
        fixture?.window.isHidden = true
        fixture = nil
        #expect(owner == nil)
        #expect(log.lastDelegate == nil)
        #expect(access.section(at: 0) == nil)
        #expect(access.item(at: IndexPath(item: 0, section: 0), as: Card.self) == nil)
        #expect(access.indexPath(for: 1) == nil)
    }

    @Test("Application subprotocol arrays open each concrete conformance before submission", arguments: [false, true])
    func applicationProtocolArray(diffable: Bool) async throws {
        let fixture = Fixture(layout: .flow(), diffable: diffable)
        defer { fixture.window.isHidden = true }
        let sections: [any ApplicationSection] = [SelfSizingSection()]
        try await fixture.owner.compose(sections.map(\.collectionSection)).apply(animated: false)
        #expect(fixture.owner.numberOfItems == 1)
        sections[0].height = 180
        try await fixture.owner.update(sections.map(\.collectionSection)).apply(animated: false)
        #expect(fixture.owner.cellPresenter(at: IndexPath(item: 0, section: 0)) != nil)
        #expect(fixture.owner.appliedRevision == 2)
    }

    @Test("Flow estimated sizes still ask the cell for its preferred size", arguments: [false, true])
    func flowSelfSizing(diffable: Bool) async throws {
        let layout = UICollectionViewFlowLayout()
        layout.estimatedItemSize = CGSize(width: 200, height: 40)
        let fixture = Fixture(layout: .flow(layout), diffable: diffable)
        defer { fixture.window.isHidden = true }
        let section = SelfSizingSection()
        try await fixture.owner.compose([section]).apply(animated: false)
        fixture.settle()
        let cell = try #require(fixture.view.cellForItem(at: IndexPath(item: 0, section: 0)) as? SelfSizingCell)
        #expect(cell.fittingCount > 0)
        #expect(fixture.frame(1)?.height == 123)
        section.height = 180
        try await section.update(animated: false)
        fixture.settle()
        #expect(fixture.frame(1)?.height == 180)
    }
}

private final class SelfSizingCell: UICollectionViewCell {
    var height: CGFloat = 0
    var fittingCount = 0
    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes)
        -> UICollectionViewLayoutAttributes {
        fittingCount += 1
        let result = attributes.copy() as! UICollectionViewLayoutAttributes
        result.size = CGSize(width: 200, height: height)
        return result
    }
}

private struct SelfSizingPresenter: CellPresenter {
    let id = 1
    let height: CGFloat
    func configure(_ cell: SelfSizingCell) {
        cell.height = height
    }
}

private final class EmptyFlowDelegate: NSObject, UICollectionViewDelegateFlowLayout {}

@MainActor private final class SelfSizingSection: ApplicationSection {
    let id = "self-sizing"
    let updateContext = SectionUpdateContext()
    var height: CGFloat = 123
    func captureContent() -> LayoutContent<FlowSectionLayout> {
        LayoutContent(
            cells: [AnyCellPresenter(SelfSizingPresenter(height: height))],
            layout: FlowSectionLayout { _ in EmptyFlowDelegate() }
        )
    }
}

@MainActor
private protocol ApplicationSection: SectionController where Layout == FlowSectionLayout {
    var height: CGFloat { get set }
}

private extension ApplicationSection {
    var collectionSection: any SectionController<FlowSectionLayout> {
        self
    }
}
