// Created by weixi on 2026/09/23.

import Parade
import Testing
import UIKit

@MainActor
@Suite("SectionStore presentation integration", .timeLimit(.minutes(1)))
struct SectionStoreIntegrationTests {
    @Test("Reconciliation stages content until the caller submits retained sections", arguments: CollectionBackend.allCases)
    func contentSubmission(backend: CollectionBackend) async throws {
        let fixture = Fixture(backend: backend)
        defer { fixture.close() }
        let store = SectionStore()
        try await store.reconcile([definition("a", items: [1], title: "old")]) { change in
            try await fixture.owner.setSections(change.presenters, animated: false)
        }
        let section = try #require(store.presenters.first as? Section<Regular>)
        let path = IndexPath(item: 0, section: 0)
        let cell = try #require(fixture.view.cellForItem(at: path))
        section.isExpanded = true
        let captures = section.captures

        let change = try await store.reconcile([definition("a", items: [1], title: "new", height: 80)]) { _ in
            Issue.record("Content-only reconciliation must not resubmit membership")
        }
        #expect(store.presenters.first === section)
        #expect(section.isExpanded)
        #expect(section.input.title == "new")
        #expect(section.captures == captures)
        #expect(fixture.owner.appliedRevision == 1)
        #expect(cell.accessibilityLabel == "old:1")
        #expect(cell.frame.height == 44)

        try await fixture.owner.update(change.retained, animated: false)
        #expect(fixture.view.cellForItem(at: path) === cell)
        #expect(cell.accessibilityLabel == "new:1")
        #expect(cell.frame.height == 80)
        #expect(fixture.owner.appliedRevision == 2)
        #expect(section.attachments == 1)
        #expect(section.detachments == 0)
    }

    @Test("Reordering and insertion preserve surviving state and retire removed attachments", arguments: CollectionBackend.allCases)
    func membershipSubmission(backend: CollectionBackend) async throws {
        let fixture = Fixture(backend: backend)
        defer { fixture.close() }
        let store = SectionStore()
        try await store.reconcile([
            definition("a", items: [1]), definition("b", items: [2]), definition("c", items: [3]),
        ]) { change in
            try await fixture.owner.setSections(change.presenters, animated: false)
        }
        let a = try #require(store.presenters.first as? Section<Regular>)
        let b = try #require(store.presenters[1] as? Section<Regular>)
        let c = try #require(store.presenters.last as? Section<Regular>)
        a.isExpanded = true

        let change = try await store.reconcile([
            definition("c", items: [3]), definition("new", items: [4]), definition("a", items: [1]),
        ]) { change in
            #expect(store.ids == [AnyHashable("a"), AnyHashable("b"), AnyHashable("c")])
            try await fixture.owner.setSections(change.presenters, animated: false)
        }
        try await fixture.owner.update(change.retained, animated: false)

        #expect(store.presenters.first === c)
        #expect(store.presenters.last === a)
        #expect(a.isExpanded)
        #expect(change.removed.first === b)
        #expect(!b.updates.isAttached)
        #expect(b.detachments == 1)
        #expect(a.attachments == 1)
        #expect(a.detachments == 0)
        #expect(c.attachments == 1)
        #expect(fixture.owner.sectionIds == [AnyHashable("c"), AnyHashable("new"), AnyHashable("a")])
        #expect(fixture.owner.indexPath(for: 2) == nil)
        #expect(fixture.owner.indexPath(for: 4) == IndexPath(item: 0, section: 1))
        #expect(fixture.view.cellForItem(at: IndexPath(item: 0, section: 2))?.accessibilityLabel == "value:1")

        await #expect(throws: CollectionUpdateError.sectionNotAttached) {
            try await b.update(animated: false)
        }
    }

    @Test("Same-ID presenter replacement detaches the old object and displays the new one", arguments: CollectionBackend.allCases)
    func replacementSubmission(backend: CollectionBackend) async throws {
        let fixture = Fixture(backend: backend)
        defer { fixture.close() }
        let store = SectionStore()
        try await store.reconcile([definition("a", items: [1])]) { change in
            try await fixture.owner.setSections(change.presenters, animated: false)
        }
        let previous = try #require(store.presenters.first as? Section<Regular>)

        let change = try await store.reconcile([
            SectionDefinition(id: "a", input: Input(items: [2], title: "replacement"), make: {
                Section<Featured>("a", input: $0)
            }, update: { $0.input = $1 }),
        ]) { change in
            try await fixture.owner.setSections(change.presenters, animated: false)
        }
        let replacement = try #require(store.presenters.first as? Section<Featured>)

        #expect(change.hasStructuralChanges)
        #expect(change.retained.isEmpty)
        #expect(change.removed.first === previous)
        #expect(!previous.updates.isAttached)
        #expect(previous.detachments == 1)
        #expect(replacement.updates.isAttached)
        #expect(replacement.attachments == 1)
        #expect(fixture.owner.indexPath(for: 1) == nil)
        #expect(fixture.view.cellForItem(at: IndexPath(item: 0, section: 0))?.accessibilityLabel == "replacement:2")
    }

    @Test("Rejected structure preserves the displayed baseline and can retry with the same survivor", arguments: CollectionBackend.allCases)
    func rejectedStructure(backend: CollectionBackend) async throws {
        let fixture = Fixture(backend: backend)
        defer { fixture.close() }
        let store = SectionStore()
        try await store.reconcile([definition("a", items: [1])]) { change in
            try await fixture.owner.setSections(change.presenters, animated: false)
        }
        let a = try #require(store.presenters.first as? Section<Regular>)
        weak var rejected: AnyObject?

        await #expect(throws: CollectionUpdateError.duplicateCellId("1")) {
            try await store.reconcile([
                definition("a", items: [4]), definition("b", items: [1]),
            ]) { change in
                rejected = change.presenters.last
                // A survivor still displays its accepted [1], so inserting another [1] is invalid.
                try await fixture.owner.setSections(change.presenters, animated: false)
            }
        }
        #expect(rejected == nil)
        #expect(store.ids == [AnyHashable("a")])
        #expect(store.presenters.first === a)
        #expect(a.input.items == [4])
        #expect(a.attachments == 1)
        #expect(a.detachments == 0)
        #expect(fixture.owner.sectionIds == [AnyHashable("a")])
        #expect(fixture.owner.appliedRevision == 1)
        #expect(fixture.view.cellForItem(at: IndexPath(item: 0, section: 0))?.accessibilityLabel == "value:1")

        let retry = try await store.reconcile([
            definition("a", items: [4]), definition("b", items: [2]),
        ]) { change in
            try await fixture.owner.setSections(change.presenters, animated: false)
        }
        try await fixture.owner.update(retry.retained, animated: false)
        #expect(store.presenters.first === a)
        #expect(fixture.owner.sectionIds == [AnyHashable("a"), AnyHashable("b")])
        #expect(fixture.owner.indexPath(for: 1) == nil)
        #expect(fixture.owner.indexPath(for: 4) == IndexPath(item: 0, section: 0))
        #expect(fixture.owner.indexPath(for: 2) == IndexPath(item: 0, section: 1))
        #expect(fixture.owner.appliedRevision == 3)
    }

    @Test("Invalid retained content leaves UIKit unchanged and a later input recovers", arguments: CollectionBackend.allCases)
    func rejectedContent(backend: CollectionBackend) async throws {
        let fixture = Fixture(backend: backend)
        defer { fixture.close() }
        let store = SectionStore()
        try await store.reconcile([definition("a", items: [1])]) { change in
            try await fixture.owner.setSections(change.presenters, animated: false)
        }
        let a = try #require(store.presenters.first)
        let invalid = try await store.reconcile([definition("a", items: [1, 1])]) { _ in
            Issue.record("Content validation belongs to presentation submission")
        }
        await #expect(throws: CollectionUpdateError.duplicateCellId("1")) {
            try await fixture.owner.update(invalid.retained, animated: false)
        }
        #expect(store.presenters.first === a)
        #expect(fixture.owner.numberOfItems == 1)
        #expect(fixture.owner.appliedRevision == 1)

        let retry = try await store.reconcile([definition("a", items: [2, 3])]) { _ in
            Issue.record("Recovery must not reconstruct membership")
        }
        try await fixture.owner.update(retry.retained, animated: false)
        #expect(store.presenters.first === a)
        #expect(fixture.owner.numberOfItems == 2)
        #expect(fixture.owner.indexPath(for: 1) == nil)
        #expect(fixture.view.cellForItem(at: IndexPath(item: 1, section: 0))?.accessibilityLabel == "value:3")
        #expect(fixture.owner.appliedRevision == 2)
    }

    @Test("Retained sections can transfer a cell in one content submission", arguments: CollectionBackend.allCases)
    func atomicContentTransfer(backend: CollectionBackend) async throws {
        let fixture = Fixture(backend: backend)
        defer { fixture.close() }
        let store = SectionStore()
        try await store.reconcile([
            definition("a", items: [1, 2]), definition("b", items: [3]),
        ]) { change in
            try await fixture.owner.setSections(change.presenters, animated: false)
        }
        let change = try await store.reconcile([
            definition("a", items: [2]), definition("b", items: [3, 1], title: "moved"),
        ]) { _ in Issue.record("A cell transfer does not change section membership") }
        try await fixture.owner.update(change.retained, animated: false)

        #expect(fixture.owner.appliedRevision == 2)
        #expect(fixture.owner.numberOfItems == 3)
        #expect(fixture.owner.indexPath(for: 1) == IndexPath(item: 1, section: 1))
        #expect(fixture.view.cellForItem(at: IndexPath(item: 1, section: 1))?.accessibilityLabel == "moved:1")
    }

    private func definition(
        _ id: String, items: [Int], title: String = "value", height: CGFloat = 44
    ) -> SectionDefinition {
        SectionDefinition(id: id, input: Input(items: items, title: title, height: height), make: {
            Section<Regular>(id, input: $0)
        }, update: { $0.input = $1 })
    }
}

private enum Regular {}
private enum Featured {}

private struct Input {
    let items: [Int]
    var title = "value"
    var height: CGFloat = 44
}

@MainActor
private final class Section<Kind>: SectionAttachmentObserving {
    let id: String
    let updates = SectionUpdateContext()
    var input: Input
    var isExpanded = false
    var captures = 0
    var attachments = 0
    var detachments = 0

    init(_ id: String, input: Input) {
        self.id = id
        self.input = input
    }

    func captureContent() -> DefaultSectionContent {
        captures += 1
        let height = input.height
        let cells = input.items.map { AnyCellPresenter(Cell(id: $0, title: input.title)) }
        return DefaultSectionContent(cells: cells) { _ in
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height))
            let item = NSCollectionLayoutItem(layoutSize: size)
            return NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [item]))
        }
    }

    func didAttach() {
        attachments += 1
    }

    func didDetach() {
        detachments += 1
    }
}

private struct Cell: CellPresenter {
    let id: Int
    let title: String
    func configure(_ cell: UICollectionViewCell) {
        cell.accessibilityLabel = "\(title):\(id)"
    }
}

@MainActor
private final class Fixture {
    let view: UICollectionView
    let owner: CollectionOrchestrator
    private let window: UIWindow

    init(backend: CollectionBackend) {
        let frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        view = UICollectionView(frame: frame, collectionViewLayout: UICollectionViewLayout())
        owner = backend.orchestrator(for: view)
        window = UIWindow(frame: frame)
        let controller = UIViewController()
        controller.view = view
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
    }
}
