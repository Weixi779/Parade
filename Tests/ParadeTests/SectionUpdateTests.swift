// Created by weixi on 2026/09/21.

import Testing
import UIKit
@testable import Parade

@MainActor
@Suite("Section-owned presentation updates")
struct SectionUpdateTests {
    @Test("Layout-only updates take effect without replacing equal cells", arguments: [false, true])
    func layoutOnly(native: Bool) async throws {
        let fixture = Fixture(native: native)
        defer { fixture.close() }
        let section = Section("a", items: [1])
        try await fixture.owner.setSections([section], animated: false)
        let path = IndexPath(item: 0, section: 0)
        let cell = try #require(fixture.view.cellForItem(at: path))
        #expect(cell.frame.height == 44)
        section.height = 96
        try await section.update(animated: false)
        #expect(fixture.view.cellForItem(at: path) === cell)
        #expect(cell.frame.height == 96)
        #expect(fixture.owner.appliedRevision == 2)
    }

    @Test("Queued local updates preserve each other and use captured layout input", arguments: [false, true])
    func capturedUpdates(native: Bool) async throws {
        let fixture = Fixture(native: native)
        defer { fixture.close() }
        let a = Section("a", items: [1])
        let b = Section("b", items: [2])
        try await fixture.owner.setSections([a, b], animated: false)
        let gate = Gate()
        fixture.source.gate = gate
        a.items = [1, 3]
        a.height = 80
        let first = Task { try await a.update(animated: false) }
        await gate.waitUntilStarted()
        a.height = 140
        b.items = [2, 4]
        let captured = Signal()
        b.onCapture = { captured.send() }
        let second = Task { try await b.update(animated: false) }
        await captured.wait()
        gate.release()
        try await first.value
        try await second.value
        #expect(fixture.owner.numberOfItems == 4)
        #expect(fixture.owner.indexPath(for: 3) == IndexPath(item: 1, section: 0))
        #expect(fixture.owner.indexPath(for: 4) == IndexPath(item: 1, section: 1))
        #expect(fixture.view.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame.height == 80)
    }

    @Test("Reordering preserves accepted contents even when live state is invalid")
    func reorderUsesBaseline() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let a = Section("a", items: [1])
        let b = Section("b", items: [2])
        try await fixture.owner.setSections([a, b], animated: false)
        let gate = Gate()
        fixture.source.gate = gate
        a.height = 80
        let update = Task { try await a.update(animated: false) }
        await gate.waitUntilStarted()
        a.height = 140
        a.items = [1, 1]
        try await withCheckedThrowingContinuation { (receipt: CheckedContinuation<Void, any Error>) in
            fixture.owner.setSections([b, a], animated: false) { receipt.resume(with: $0) }
            gate.release()
        }
        try await update.value
        #expect(fixture.owner.sectionIds == [AnyHashable("b"), AnyHashable("a")])
        #expect(fixture.view.layoutAttributesForItem(at: IndexPath(item: 0, section: 1))?.frame.height == 80)
    }

    @Test(
        "Reordering during initial attachment ignores unused invalid live contents",
        arguments: [false, true], [false, true]
    )
    func reorderDuringInitialAttachment(native: Bool, initialIsExecuting: Bool) async throws {
        let fixture = Fixture(native: native)
        defer { fixture.close() }
        let a = Section("a", items: [1])
        let b = Section("b", items: [2])
        let gate = Gate()
        fixture.source.gate = gate
        let first = Task {
            try await fixture.owner.setSections(initialIsExecuting ? [a, b] : [], animated: false)
        }
        await gate.waitUntilStarted()
        var initial: Result<Void, CollectionUpdateError>?
        let initialCompleted = Signal()
        if !initialIsExecuting {
            fixture.owner.setSections([a, b], animated: false) {
                initial = $0
                initialCompleted.send()
            }
        }

        a.items = [1, 1]
        a.height = 96
        let result: Result<Void, CollectionUpdateError> = await withCheckedContinuation { receipt in
            fixture.owner.setSections([b, a], animated: false) { receipt.resume(returning: $0) }
            gate.release()
        }
        try await first.value
        if !initialIsExecuting {
            await initialCompleted.wait()
            try #require(initial).get()
        }
        try result.get()

        #expect(fixture.owner.sectionIds == [AnyHashable("b"), AnyHashable("a")])
        #expect(fixture.owner.numberOfItems == 2)
        let path = IndexPath(item: 0, section: 1)
        #expect(fixture.owner.indexPath(for: 1) == path)
        #expect(fixture.view.layoutAttributesForItem(at: path)?.frame.height == 44)
        #expect(fixture.owner.appliedRevision == (initialIsExecuting ? 2 : 3))
    }

    @Test("Reattachment after a queued removal uses the submission's captured presentation", arguments: [false, true])
    func queuedReattachment(native: Bool) async throws {
        let fixture = Fixture(native: native)
        defer { fixture.close() }
        let section = Section("a", items: [1])
        try await fixture.owner.setSections([section], animated: false)
        let gate = Gate()
        fixture.source.gate = gate
        let first = Task { try await section.update(animated: false) }
        await gate.waitUntilStarted()

        var removal: Result<Void, CollectionUpdateError>?
        fixture.owner.setSections([], animated: false) { removal = $0 }
        section.items = [2]
        section.height = 96
        try await withCheckedThrowingContinuation { (receipt: CheckedContinuation<Void, any Error>) in
            fixture.owner.setSections([section], animated: false) { receipt.resume(with: $0) }
            section.items = [3]
            section.height = 144
            gate.release()
        }
        try await first.value
        try #require(removal).get()

        let path = IndexPath(item: 0, section: 0)
        #expect(fixture.owner.indexPath(for: 1) == nil)
        #expect(fixture.owner.indexPath(for: 2) == path)
        #expect(fixture.owner.indexPath(for: 3) == nil)
        #expect(fixture.view.cellForItem(at: path)?.accessibilityLabel == "2")
        #expect(fixture.view.layoutAttributesForItem(at: path)?.frame.height == 96)
        #expect(section.updates.isAttached)
        #expect(fixture.owner.appliedRevision == 4)
    }

    @Test("An old instance cannot update a replacement with the same ID")
    func staleInstance() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let old = Section("a", items: [1])
        let replacement = Section("a", items: [2])
        try await fixture.owner.setSections([old], animated: false)
        let gate = Gate()
        fixture.source.gate = gate
        let removal = Task { try await fixture.owner.setSections([], animated: false) }
        await gate.waitUntilStarted()
        let captured = Signal()
        old.onCapture = { captured.send() }
        let lateUpdate = Task { try await old.update(animated: false) }
        await captured.wait()
        try await withCheckedThrowingContinuation { (receipt: CheckedContinuation<Void, any Error>) in
            fixture.owner.setSections([replacement], animated: false) { receipt.resume(with: $0) }
            gate.release()
        }
        try await removal.value
        await #expect(throws: CollectionUpdateError.staleSectionInstance("a")) { try await lateUpdate.value }
        #expect(!old.updates.isAttached)
        #expect(replacement.updates.isAttached)
        #expect(fixture.owner.indexPath(for: 1) == nil)
        #expect(fixture.owner.indexPath(for: 2) == IndexPath(item: 0, section: 0))
    }

    @Test("Execution rejects a global ID conflict, settles its receipt, and continues")
    func globalConflict() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let a = Section("a", items: [1])
        let b = Section("b", items: [2])
        try await fixture.owner.setSections([a, b], animated: false)
        let gate = Gate()
        fixture.source.gate = gate
        a.items = [9]
        let first = Task { try await a.update(animated: false) }
        await gate.waitUntilStarted()
        b.items = [9]
        let captured = Signal()
        b.onCapture = { captured.send() }
        let second = Task { try await b.update(animated: false) }
        await captured.wait()
        gate.release()
        try await first.value
        await #expect(throws: CollectionUpdateError.duplicateCellId("9")) { try await second.value }
        b.items = [10]
        try await b.update(animated: false)
        #expect(fixture.owner.appliedRevision == 3)
        #expect(fixture.owner.indexPath(for: 9) == IndexPath(item: 0, section: 0))
        #expect(fixture.owner.indexPath(for: 10) == IndexPath(item: 0, section: 1))
    }

    @Test("Multiple sections transfer a cell atomically", arguments: [false, true])
    func transfer(native: Bool) async throws {
        let fixture = Fixture(native: native)
        defer { fixture.close() }
        let a = Section("a", items: [1, 2])
        let b = Section("b", items: [3])
        try await fixture.owner.setSections([a, b], animated: false)
        a.items = [2]
        b.items = [3, 1]
        try await fixture.owner.update([a, b], animated: false)
        #expect(fixture.owner.indexPath(for: 1) == IndexPath(item: 1, section: 1))
        #expect(fixture.owner.numberOfItems == 3)
    }

    @Test("An in-flight attachment reserves the section for one collection")
    func attachmentReservation() async throws {
        let first = Fixture()
        let second = Fixture()
        defer { first.close(); second.close() }
        let section = Section("a", items: [1])
        let gate = Gate()
        first.source.gate = gate
        let attachment = Task { try await first.owner.setSections([section], animated: false) }
        await gate.waitUntilStarted()
        #expect(!section.updates.isAttached)
        await #expect(throws: CollectionUpdateError.sectionAlreadyAttached) {
            try await second.owner.setSections([section], animated: false)
        }
        gate.release()
        try await attachment.value
        try await first.owner.setSections([], animated: false)
        try await second.owner.setSections([section], animated: false)
        #expect(section.updates.isAttached)
    }

    @Test("Structural stages retain layout with their section metadata")
    func stagedLayoutIdentity() throws {
        let a = Section("a", items: [1, 2])
        let b = Section("b", items: [3])
        let oldA = CapturedSection(capturing: a)
        let oldB = CapturedSection(capturing: b)
        let source = try CollectionComposition([oldA, oldB])
        a.height = 90
        a.items = [2]
        b.items = [3, 1]
        let target = try CollectionComposition([CapturedSection(capturing: b), CapturedSection(capturing: a)])
        let plan = try CollectionUpdatePlan(from: source, to: target)
        for batch in plan.batches {
            for section in batch.sections {
                #expect(section.layout === source.sectionsById[section.id]?.layout)
            }
        }
        #expect(plan.content.hasLayoutUpdates)
    }
}

private struct Cell: CellPresenter {
    let id: Int
    func configure(_ cell: UICollectionViewCell) { cell.accessibilityLabel = String(id) }
}

private struct Presentation: SectionPresentation {
    let cells: [AnyCellPresenter]
    let height: CGFloat

    @MainActor
    func makeLayout(in environment: any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height))
        return NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]))
    }
}

@MainActor
private final class Section: SectionPresenter {
    let id: String
    let updates = SectionUpdateContext()
    var items: [Int]
    var height: CGFloat = 44
    var onCapture: (() -> Void)?

    init(_ id: String, items: [Int]) { self.id = id; self.items = items }

    func capturePresentation() -> Presentation {
        let result = Presentation(cells: items.map { AnyCellPresenter(Cell(id: $0)) }, height: height)
        onCapture?()
        return result
    }
}

@MainActor
private final class Signal {
    private var sent = false
    private var waiter: CheckedContinuation<Void, Never>?
    func send() { sent = true; waiter?.resume(); waiter = nil }
    func wait() async {
        if !sent { await withCheckedContinuation { waiter = $0 } }
    }
}

@MainActor
private final class Gate {
    private let started = Signal()
    private var receipt: CheckedContinuation<Void, Never>?
    func pause() async {
        await withCheckedContinuation { receipt = $0; started.send() }
    }
    func waitUntilStarted() async { await started.wait() }
    func release() { receipt?.resume(); receipt = nil }
}

@MainActor
private final class ControlledSource: CollectionDataSource {
    let base: any CollectionDataSource
    var gate: Gate?
    init(_ base: any CollectionDataSource) { self.base = base }
    var dataSource: any UICollectionViewDataSource { base.dataSource }
    var sectionIds: [AnyHashable] { base.sectionIds }
    var numberOfSections: Int { base.numberOfSections }
    var numberOfItems: Int { base.numberOfItems }
    var isEmpty: Bool { base.isEmpty }
    func sectionId(at index: Int) -> AnyHashable? { base.sectionId(at: index) }
    func sectionIndex(for id: AnyHashable) -> Int? { base.sectionIndex(for: id) }
    func indexPath(for id: AnyHashable) -> IndexPath? { base.indexPath(for: id) }
    func cellPresenter(at indexPath: IndexPath) -> AnyCellPresenter? { base.cellPresenter(at: indexPath) }
    func supplementaryPresenter(ofKind kind: String, at indexPath: IndexPath) -> AnySupplementaryPresenter? {
        base.supplementaryPresenter(ofKind: kind, at: indexPath)
    }
    func layoutSection(at index: Int, environment: any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? {
        base.layoutSection(at: index, environment: environment)
    }
    func apply(from source: CollectionComposition, to target: CollectionComposition, animated: Bool, mode: CollectionUpdateMode) async -> [CollectionDiagnostic] {
        if let gate { self.gate = nil; await gate.pause() }
        return await base.apply(from: source, to: target, animated: animated, mode: mode)
    }
}

@MainActor
private final class Fixture {
    let view: UICollectionView
    let owner: CollectionOrchestrator
    let source: ControlledSource
    private let window: UIWindow

    init(native: Bool = false) {
        let frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        let view = UICollectionView(frame: frame, collectionViewLayout: UICollectionViewLayout())
        self.view = view
        var controlled: ControlledSource!
        owner = CollectionOrchestrator(collectionView: view) { view, cell, supplementary in
            let base: any CollectionDataSource = native
                ? DiffableCollectionDataSource(collectionView: view, cellProvider: cell, supplementaryProvider: supplementary)
                : DefaultCollectionDataSource(collectionView: view, cellProvider: cell, supplementaryProvider: supplementary)
            let source = ControlledSource(base)
            controlled = source
            return source
        }
        source = controlled
        window = UIWindow(frame: frame)
        let controller = UIViewController()
        controller.view = view
        window.rootViewController = controller
        window.isHidden = false
    }
    func close() { window.isHidden = true }
}
