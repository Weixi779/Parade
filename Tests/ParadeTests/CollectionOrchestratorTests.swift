//
//  Created by weixi on 2026/9/17.
//

import Testing
import UIKit
@testable import Parade

@MainActor
@Suite("Collection orchestration")
struct CollectionOrchestratorTests {
    @Test("Content-equal submissions refresh actions without reconfiguring the cell", arguments: CollectionBackend.allCases)
    func behaviorOnlyUpdate(backend: CollectionBackend) async throws {
        let fixture = CollectionFixture(backend: backend)
        defer { fixture.close() }
        let events = Events()
        try await fixture.orchestrator.setSections([TestSection(id: "messages", cells: [
            AnyCellPresenter(TextPresenter(id: 1, text: "Hello", action: "old", events: events)),
        ])], animated: false)
        let cell = try #require(fixture.collectionView.cellForItem(at: IndexPath(
            item: 0,
            section: 0
        )) as? TextCell)
        let configurations = cell.configurations
        fixture.collectionView.resetCounts()
        try await fixture.orchestrator.setSections([TestSection(id: "messages", cells: [
            AnyCellPresenter(TextPresenter(id: 1, text: "Hello", action: "new", events: events)),
        ])], animated: false)
        cell.action?()
        fixture.collectionView.delegate?.collectionView?(
            fixture.collectionView,
            didSelectItemAt: IndexPath(item: 0, section: 0)
        )
        #expect(events.actions == ["new", "selected:new"])
        #expect(cell.configurations == configurations)
        if backend == .manual {
            // The captured layout is invalidated, but equal cells are not reconfigured.
            #expect(fixture.collectionView.batches == 1)
            #expect(fixture.collectionView.reloads == 0)
        }
        #expect(fixture.orchestrator.appliedRevision == 2)
    }

    @Test("Content updates retain compatible cells and invalidate their self sizing", arguments: CollectionBackend.allCases)
    func contentAndSelfSizing(backend: CollectionBackend) async throws {
        let fixture = CollectionFixture(backend: backend)
        defer { fixture.close() }
        try await fixture.orchestrator.setSections([textSection("messages", [1])], animated: false)
        let path = IndexPath(item: 0, section: 0)
        let cell = try #require(fixture.collectionView.cellForItem(at: path) as? TextCell)
        let oldHeight = cell.frame.height
        fixture.collectionView.resetCounts()
        let longText = String(repeating: "A long message wraps onto another line. ", count: 12)
        try await fixture.orchestrator.setSections([TestSection(id: "messages", cells: [
            AnyCellPresenter(TextPresenter(id: 1, text: longText)),
        ])], animated: false)
        let updated = try #require(fixture.collectionView.cellForItem(at: path) as? TextCell)
        #expect(updated === cell)
        #expect(updated.label.text == longText)
        #expect(updated.frame.height > oldHeight)
        if backend == .manual {
            #expect(fixture.collectionView.reconfigured == [path])
            #expect(fixture.collectionView.replaced.isEmpty)
        }
    }

    @Test("The same Id can change its concrete cell registration", arguments: CollectionBackend.allCases)
    func replacingCellType(backend: CollectionBackend) async throws {
        let fixture = CollectionFixture(backend: backend)
        defer { fixture.close() }
        try await fixture.orchestrator.setSections([textSection("messages", [1])], animated: false)
        fixture.collectionView.resetCounts()
        try await fixture.orchestrator.setSections([TestSection(id: "messages", cells: [
            AnyCellPresenter(ColorPresenter(id: 1, title: "Notice")),
        ])], animated: false)
        let path = IndexPath(item: 0, section: 0)
        #expect(fixture.collectionView.cellForItem(at: path) is ColorCell)
        if backend == .manual {
            #expect(fixture.collectionView.replaced == [path])
            #expect(fixture.collectionView.reconfigured.isEmpty)
        }
        #expect(fixture.orchestrator.indexPath(for: 1) == path)
    }

    @Test("A moved cell can change type while both section endpoints change", arguments: CollectionBackend.allCases)
    func movedCellChangesType(backend: CollectionBackend) async throws {
        let fixture = CollectionFixture(backend: backend)
        defer { fixture.close() }
        try await fixture.orchestrator.setSections(
            [textSection("removed", [1, 2]), textSection("retained", [3])],
            animated: false
        )
        try await fixture.orchestrator.setSections([
            TestSection(
                id: "inserted",
                cells: [AnyCellPresenter(ColorPresenter(id: 1, title: "Moved notice"))]
            ),
            textSection("retained", [3, 2]),
        ], animated: true)
        let path = IndexPath(item: 0, section: 0)
        #expect(fixture.collectionView.cellForItem(at: path) is ColorCell)
        #expect(fixture.orchestrator.sectionIds == [
            AnyHashable("inserted"),
            AnyHashable("retained")
        ])
        #expect(fixture.orchestrator.indexPath(for: 2) == IndexPath(item: 1, section: 1))
        #expect(fixture.orchestrator.numberOfItems == 3)
    }

    @Test("Header-only sections survive and compatible supplementary content updates", arguments: CollectionBackend.allCases)
    func supplementaryContentAndBehavior(backend: CollectionBackend) async throws {
        let fixture = CollectionFixture(headers: true, backend: backend)
        defer { fixture.close() }
        let events = Events()
        let old = TestSection(id: "empty-with-header", cells: [], supplementaryViews: [
            AnySupplementaryPresenter(HeaderPresenter(
                id: "header",
                text: "First",
                action: "old",
                events: events
            )),
        ])
        try await fixture.orchestrator.setSections([old], animated: false)
        let path = IndexPath(item: 0, section: 0)
        let view = try #require(fixture.collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader,
            at: path
        ) as? HeaderView)
        #expect(fixture.orchestrator.numberOfSections == 1)
        #expect(fixture.orchestrator.numberOfItems == 0)
        fixture.collectionView.resetCounts()
        let updated = TestSection(id: "empty-with-header", cells: [], supplementaryViews: [
            AnySupplementaryPresenter(HeaderPresenter(
                id: "header",
                text: "Second",
                action: "new",
                events: events
            )),
        ])
        try await fixture.orchestrator.setSections([updated], animated: false)
        view.action?()
        #expect(view.label.text == "Second")
        #expect(events.actions == ["new"])
        if backend == .manual {
            #expect(fixture.collectionView.sectionReloads.isEmpty)
            #expect(fixture.collectionView.batches == 1)
        }
    }

    @Test("Supplementary registration changes replace the view", arguments: CollectionBackend.allCases)
    func replacingSupplementaryType(backend: CollectionBackend) async throws {
        let fixture = CollectionFixture(headers: true, backend: backend)
        defer { fixture.close() }
        try await fixture.orchestrator.setSections([TestSection(id: "s", cells: [], supplementaryViews: [
            AnySupplementaryPresenter(HeaderPresenter(id: "h", text: "Header")),
        ])], animated: false)
        fixture.collectionView.resetCounts()
        try await fixture.orchestrator.setSections([TestSection(id: "s", cells: [], supplementaryViews: [
            AnySupplementaryPresenter(AlternateHeaderPresenter(id: "h")),
        ])], animated: false)
        let view = fixture.collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader,
            at: IndexPath(
                item: 0,
                section: 0
            )
        )
        #expect(view is AlternateHeaderView)
        if backend == .manual {
            #expect(fixture.collectionView.sectionReloads == IndexSet(integer: 0))
        }
    }

    @Test("Layout resolves header additions and removals from the current stage", arguments: CollectionBackend.allCases)
    func supplementaryTopologyFollowsDisplayVersion(backend: CollectionBackend) async throws {
        let fixture = CollectionFixture(dynamicHeaders: true, backend: backend)
        defer { fixture.close() }
        try await fixture.orchestrator.setSections([textSection("section", [1, 2])], animated: false)
        let path = IndexPath(item: 0, section: 0)
        let kind = UICollectionView.elementKindSectionHeader
        #expect(fixture.orchestrator.supplementaryPresenter(ofKind: kind, at: path) == nil)
        let withHeader = textSection("section", [2, 3, 1])
        withHeader.supplementaryViews = [AnySupplementaryPresenter(HeaderPresenter(
            id: "header",
            text: "Added"
        ))]
        try await fixture.orchestrator.setSections([withHeader], animated: false)
        let header = try #require(fixture.collectionView.supplementaryView(
            forElementKind: kind,
            at: path
        ) as? HeaderView)
        #expect(header.label.text == "Added")
        try await fixture.orchestrator.setSections([textSection("section", [3, 1])], animated: false)
        #expect(fixture.orchestrator.supplementaryPresenter(ofKind: kind, at: path) == nil)
        #expect(fixture.collectionView.supplementaryView(forElementKind: kind, at: path) == nil)
        #expect(fixture.collectionView.numberOfItems(inSection: 0) == 2)
    }

    @Test("Invalid submissions leave the applied composition and UIKit untouched", arguments: CollectionBackend.allCases)
    func duplicateValidation(backend: CollectionBackend) async throws {
        let fixture = CollectionFixture(backend: backend)
        defer { fixture.close() }
        try await fixture.orchestrator.setSections([textSection("one", [1])], animated: false)
        fixture.collectionView.resetCounts()
        await #expect(throws: CollectionUpdateError.duplicateCellId("2")) {
            try await fixture.orchestrator.setSections(
                [textSection("one", [2]), textSection("two", [2])],
                animated: false
            )
        }
        await #expect(throws: CollectionUpdateError.duplicateSectionId("same")) {
            try await fixture.orchestrator.setSections(
                [textSection("same", []), textSection("same", [])],
                animated: false
            )
        }
        #expect(fixture.orchestrator.sectionIds == [AnyHashable("one")])
        #expect(fixture.orchestrator.indexPath(for: 1) == IndexPath(item: 0, section: 0))
        #expect(fixture.collectionView.batches == 0)
        #expect(fixture.orchestrator.appliedRevision == 1)
    }

    @Test(
        "Content rejection settles in FIFO order without advancing the baseline or blocking updates",
        arguments: [CollectionUpdateMode.diff, .reload]
    )
    func rejectedInputBetweenUpdates(mode: CollectionUpdateMode) async throws {
        let fixture = CollectionFixture()
        defer { fixture.close() }
        let owner = fixture.orchestrator
        try await owner.setSections([textSection("s", [0])], animated: false)
        fixture.collectionView.resetCounts()
        var completions: [String] = []
        var applied = 0
        var diagnostics: [CollectionDiagnostic] = []
        owner.onDidApply = { _ in applied += 1 }
        owner.onDiagnostic = { diagnostics.append($0) }

        await withCheckedContinuation { continuation in
            owner.setSections([textSection("s", [1])], animated: true, mode: mode) { result in
                if case .success = result { completions.append("first") }
            }
            owner.setSections([textSection("s", [2, 2])], mode: mode) { result in
                #expect(owner.appliedRevision == 2)
                if case .failure(.duplicateCellId("2")) = result { completions.append("rejected") }
            }
            owner.setSections([textSection("s", [3])], animated: false, mode: mode) { result in
                if case .success = result { completions.append("last") }
                continuation.resume()
            }
        }
        #expect(completions == ["first", "rejected", "last"])
        #expect(applied == 2)
        #expect(owner.appliedRevision == 3)
        #expect(!owner.isApplying)
        #expect(owner.indexPath(for: 3) == IndexPath(item: 0, section: 0))
        #expect(owner.indexPath(for: 2) == nil)
        #expect(diagnostics.count == 1)
        let diagnostic = try #require(diagnostics.first)
        #expect(diagnostic.reason == .invalidUpdate(.duplicateCellId("2")))
        #expect(diagnostic.recovery == .rejectedUpdate)
        #expect(diagnostic.locations == [.init(section: 0, item: 0), .init(section: 0, item: 1)])
        #expect(fixture.collectionView.reloads == (mode == .reload ? 2 : 0))
        #expect(fixture.collectionView.maximumActiveBatches <= 1)
    }

    @Test("Public algorithm injection preserves alternative moves through UIKit")
    func alternativeAlgorithm() async throws {
        let fixture = CollectionFixture(diffAlgorithm: StandardLibraryDiff())
        defer { fixture.close() }
        let owner = fixture.orchestrator
        var diagnostics: [CollectionDiagnostic] = []
        owner.onDiagnostic = { diagnostics.append($0) }
        try await owner.setSections([textSection("s", [0, 1, 2, 3])], animated: false)
        fixture.collectionView.resetCounts()
        try await owner.setSections([textSection("s", [1, 2, 3, 0])], animated: false)
        #expect(fixture.collectionView.movedItems.count == 1)
        #expect(fixture.collectionView.movedItems.first?.from == IndexPath(item: 0, section: 0))
        #expect(fixture.collectionView.movedItems.first?.to == IndexPath(item: 3, section: 0))
        #expect(owner.indexPath(for: 0) == IndexPath(item: 3, section: 0))
        #expect(fixture.collectionView.reloads == 0)
        #expect(diagnostics.isEmpty)
    }

    enum AlgorithmFailure: CaseIterable, Sendable, SectionedDiffAlgorithm {
        case thrownError, invalidCoordinate, incompleteResult, conflictingMoves, invalidUpdate

        func diff<Section: DiffableSection>(from source: [Section],
                                            to target: [Section]) throws -> SectionedChanges {
            var changes = try SectionedDiff().diff(from: source, to: target)
            guard source.first?.items.count == 1,
                  target.first?.items.count == 1 else { return changes }
            switch self {
            case .thrownError:
                throw CollectionUpdatePlan.ValidationError("Injected algorithm failure")
            case .invalidCoordinate:
                changes.deletedItems = [.init(section: 0, item: 99)]
            case .incompleteResult:
                return SectionedChanges()
            case .conflictingMoves:
                changes.movedItems = [(.init(section: 0, item: 0), .init(section: 0, item: 0))]
            case .invalidUpdate:
                changes.updatedSections.insert(99)
            }
            return changes
        }
    }

    @Test(
        "Algorithm failures reload a valid target before any batch and permit diagnostic reentrancy",
        arguments: AlgorithmFailure.allCases
    )
    func algorithmRecovery(failure: AlgorithmFailure) async throws {
        let fixture = CollectionFixture(diffAlgorithm: failure)
        defer { fixture.close() }
        let owner = fixture.orchestrator
        try await owner.setSections([textSection("s", [1])], animated: false)
        fixture.collectionView.resetCounts()
        var diagnostics: [CollectionDiagnostic] = []
        var completions: [String] = []
        await withCheckedContinuation { continuation in
            owner.onDiagnostic = { diagnostic in
                diagnostics.append(diagnostic)
                #expect(owner.appliedRevision == 2)
                #expect(owner.indexPath(for: 2) == IndexPath(item: 0, section: 0))
                #expect(fixture.collectionView.batches == 0)
                #expect(fixture.collectionView.reloads == 1)
                #expect(fixture.collectionView.cellForItem(at: .init(
                    item: 0,
                    section: 0
                )) is TextCell)
                owner.setSections([textSection("s", [2, 3])], animated: false) { result in
                    if case .success = result { completions.append("next") }
                    continuation.resume()
                }
            }
            owner.setSections([textSection("s", [2])], animated: false) { result in
                if case .success = result { completions.append("recovered") }
            }
        }
        #expect(completions == ["recovered", "next"])
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.recovery == .reloadedTarget)
        if case .invalidDiff = diagnostics.first?.reason {}
        else { Issue.record("Missing diff diagnostic") }
        #expect(owner.appliedRevision == 3)
        #expect(owner.numberOfItems == 2)
        #expect(owner.indexPath(for: 3) == IndexPath(item: 1, section: 0))
        #expect(!owner.isApplying)
        #expect(fixture.collectionView.maximumActiveBatches <= 1)
    }

    @Test(
        "An invalid first submission is reported outside apply and can be retried from its diagnostic"
    )
    func initialRejectionRecovery() async {
        let fixture = CollectionFixture()
        defer { fixture.close() }
        let owner = fixture.orchestrator
        var inApply = false
        var failures = 0
        var successes = 0
        await withCheckedContinuation { continuation in
            owner.onDiagnostic = { _ in
                #expect(!inApply)
                #expect(owner.appliedRevision == 0)
                #expect(owner.numberOfSections == 0)
                owner.setSections([textSection("s", [1])], animated: false) { result in
                    if case .success = result { successes += 1 }
                    continuation.resume()
                }
            }
            inApply = true
            owner.setSections([textSection("s", [1, 1])], mode: .reload) { result in
                if case .failure = result { failures += 1 }
            }
            inApply = false
        }
        #expect(failures == 1 && successes == 1)
        #expect(owner.appliedRevision == 1)
        #expect(owner.numberOfItems == 1)
    }

    @Test("Queued and callback-reentrant submissions finish in FIFO order", arguments: CollectionBackend.allCases)
    func queuedUpdates(backend: CollectionBackend) async throws {
        let fixture = CollectionFixture(backend: backend)
        defer { fixture.close() }
        var completions: [Int] = []
        await withCheckedContinuation { continuation in
            fixture.orchestrator.onDidApply = { orchestrator in
                if orchestrator.appliedRevision == 1 {
                    orchestrator.setSections([textSection("s", [3])], animated: false) { result in
                        if case .success = result { completions.append(3) }
                        continuation.resume()
                    }
                }
            }
            fixture.orchestrator.setSections([textSection("s", [1])], animated: true) { result in
                if case .success = result { completions.append(1) }
            }
            fixture.orchestrator.setSections([textSection("s", [2])], animated: true) { result in
                if case .success = result { completions.append(2) }
            }
        }
        #expect(completions == [1, 2, 3])
        if backend == .manual {
            #expect(fixture.collectionView.maximumActiveBatches == 1)
        }
        #expect(fixture.orchestrator.indexPath(for: 3) == IndexPath(item: 0, section: 0))
        #expect(fixture.orchestrator.indexPath(for: 1) == nil)
        #expect(fixture.orchestrator.appliedRevision == 3)
    }

    @Test("Section composition is captured when submitted", arguments: CollectionBackend.allCases)
    func capturedComposition(backend: CollectionBackend) async throws {
        let fixture = CollectionFixture(backend: backend)
        defer { fixture.close() }
        let mutable = MutableSection(
            id: "section",
            cells: [AnyCellPresenter(TextPresenter(id: 1, text: "original"))]
        )
        await withCheckedContinuation { continuation in
            fixture.orchestrator.setSections([mutable], animated: false) { _ in continuation.resume() }
            mutable.cells = []
        }
        #expect(fixture.orchestrator.numberOfItems == 1)
        #expect(fixture.collectionView.numberOfItems(inSection: 0) == 1)
    }

    @Test("Empty content preserves the application's background and scrolling policy", arguments: CollectionBackend.allCases)
    func emptyContent(backend: CollectionBackend) async throws {
        let fixture = CollectionFixture(backend: backend)
        defer { fixture.close() }
        let background = UIView()
        let empty = UIView()
        fixture.collectionView.backgroundView = background
        fixture.collectionView.isScrollEnabled = false
        fixture.orchestrator.emptyViewProvider = { empty }
        try await fixture.orchestrator.setSections([textSection("empty", [])], animated: false)
        #expect(fixture.collectionView.backgroundView === empty)
        #expect(!fixture.collectionView.isScrollEnabled)
        #expect(fixture.orchestrator.numberOfSections == 1)
        try await fixture.orchestrator.setSections([textSection("empty", [1])], animated: false)
        #expect(fixture.collectionView.backgroundView === background)
        #expect(!fixture.collectionView.isScrollEnabled)
    }

    @Test("Off-window updates install a reload without scheduling UIKit batches", arguments: CollectionBackend.allCases)
    func offWindow(backend: CollectionBackend) async throws {
        let collectionView = RecordingCollectionView(
            frame: .zero,
            collectionViewLayout: UICollectionViewFlowLayout()
        )
        let orchestrator = backend.orchestrator(for: collectionView)
        collectionView.resetCounts()
        try await orchestrator.setSections([textSection("one", [1, 2])], animated: false)
        if backend == .manual {
            #expect(collectionView.reloads == 1)
            #expect(collectionView.batches == 0)
        }
        #expect(orchestrator.numberOfItems == 2)
        #expect(orchestrator.appliedRevision == 1)
    }

    @Test(
        "Section transfers, empty endpoints, reversals and content changes reach UIKit",
        arguments: [false, true], CollectionBackend.allCases
    )
    func structuralTransitions(animated: Bool, backend: CollectionBackend) async throws {
        let fixture = CollectionFixture(backend: backend)
        defer { fixture.close() }
        let cases: [[(String, [Int])]] = [
            [("featured", [1, 2]), ("ranking", [3, 4, 5, 6]), ("recommendations", [7, 8, 9])],
            [("featured", [1]), ("ranking", [3, 2, 5]), ("recommendations", [7, 8, 9, 4, 6])],
            [
                ("new", [2, 4]),
                ("recommendations", [9, 8, 7]),
                ("ranking", [3, 5]),
                ("featured", [1, 6])
            ],
            [("new", [2, 4, 1, 3, 5]), ("recommendations", [9, 8, 7, 6])],
            [("recommendations", [7, 8, 9]), ("new", [5, 3, 1, 4, 2, 6])],
            [("empty", []), ("replacement", [9, 1, 10])],
            [],
            [("single", [0, 1, 2])],
            [("single", [2, 1, 0])],
            [("single", [0, 1, 2])],
        ]
        for (generation, value) in cases.enumerated() {
            let sections = value.map { pair in
                TestSection(
                    id: pair.0,
                    cells: pair.1.map { AnyCellPresenter(TextPresenter(
                        id: $0,
                        text: "\(generation):\($0)"
                    )) }
                )
            }
            try await fixture.orchestrator.setSections(sections, animated: animated)
            #expect(fixture.orchestrator.sectionIds == value.map { AnyHashable($0.0) })
            #expect(fixture.collectionView.numberOfSections == value.count)
            for (section, pair) in value.enumerated() {
                #expect(fixture.collectionView.numberOfItems(inSection: section) == pair.1.count)
                for (item, id) in pair.1.enumerated() {
                    #expect(fixture.orchestrator.indexPath(for: id) == IndexPath(
                        item: item,
                        section: section
                    ))
                }
            }
            for path in fixture.collectionView.indexPathsForVisibleItems {
                let cell = try #require(fixture.collectionView.cellForItem(at: path) as? TextCell)
                #expect(cell.label.text == "\(generation):\(value[path.section].1[path.item])")
            }
        }
        if backend == .manual {
            #expect(fixture.collectionView.maximumActiveBatches == 1)
        }
    }
}

@MainActor
private func textSection(_ id: String, _ items: [Int]) -> TestSection {
    TestSection(
        id: id,
        cells: items.map { AnyCellPresenter(TextPresenter(id: $0, text: "Item \($0)")) }
    )
}

@MainActor
private final class TestSection: SectionPresenter {
    let updates = SectionUpdateContext()
    let id: String
    var cells: [AnyCellPresenter]
    var supplementaryViews: [AnySupplementaryPresenter]

    init(id: String, cells: [AnyCellPresenter], supplementaryViews: [AnySupplementaryPresenter] = []) {
        self.id = id
        self.cells = cells
        self.supplementaryViews = supplementaryViews
    }

    func capturePresentation() -> DefaultSectionPresentation {
        testPresentation(cells: cells, supplementaryViews: supplementaryViews)
    }
}

@MainActor
private final class MutableSection: SectionPresenter {
    let updates = SectionUpdateContext()
    func capturePresentation() -> DefaultSectionPresentation { testPresentation(cells: cells) }
    let id: String
    var cells: [AnyCellPresenter]
    init(id: String, cells: [AnyCellPresenter]) {
        self.id = id
        self.cells = cells
    }
}

@MainActor
private final class Events {
    var actions: [String] = []
}

@MainActor
private final class TextCell: UICollectionViewCell {
    let label = UILabel()
    var configurations = 0
    var action: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private struct TextPresenter: CellPresenter, CellSelectionHandling {
    let id: Int
    let text: String
    var action: String = ""
    var events: Events?
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.text == rhs.text }
    func configure(_ cell: TextCell) {
        cell.label.text = text
        cell.configurations += 1
    }

    func setBehaviors(_ cell: TextCell) { cell.action = { events?.actions.append(action) } }
    func didSelect(_ cell: TextCell) { events?.actions.append("selected:\(action)") }
}

@MainActor
private final class ColorCell: UICollectionViewCell {}

private struct ColorPresenter: CellPresenter {
    let id: Int
    let title: String
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }
    func configure(_ cell: ColorCell) {
        cell.accessibilityLabel = title
        cell.backgroundColor = .systemBlue
    }
}

@MainActor
private final class HeaderView: UICollectionReusableView {
    let label = UILabel()
    var action: (() -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
    }
}

private struct HeaderPresenter: SupplementaryPresenter {
    let id: String
    let text: String
    var action: String = ""
    var events: Events?
    var elementKind: String { Self.headerKind }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.text == rhs.text }
    func configure(_ view: HeaderView) { view.label.text = text }
    func setBehaviors(_ view: HeaderView) { view.action = { events?.actions.append(action) } }
}

@MainActor
private final class AlternateHeaderView: UICollectionReusableView {}

private struct AlternateHeaderPresenter: SupplementaryPresenter {
    let id: String
    var elementKind: String { Self.headerKind }
    static func == (lhs: Self, rhs: Self) -> Bool { true }
    func configure(_ view: AlternateHeaderView) { view.backgroundColor = .systemOrange }
}

@MainActor
private final class CollectionFixture {
    let window: UIWindow
    let collectionView: RecordingCollectionView
    let orchestrator: CollectionOrchestrator

    init(
        headers: Bool = false,
        dynamicHeaders: Bool = false,
        backend: CollectionBackend = .manual,
        diffAlgorithm: any SectionedDiffAlgorithm = SectionedDiff()
    ) {
        let lookup = LayoutLookup()
        let layout = UICollectionViewCompositionalLayout { index, _ in
            let item = NSCollectionLayoutItem(layoutSize: .init(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(44)
            ))
            let group = NSCollectionLayoutGroup.vertical(
                layoutSize: .init(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(44)
                ),
                subitems: [item]
            )
            let section = NSCollectionLayoutSection(group: group)
            let hasDynamicHeader = dynamicHeaders && lookup.owner?.supplementaryPresenter(
                ofKind: UICollectionView.elementKindSectionHeader,
                at: IndexPath(
                    item: 0,
                    section: index
                )
            ) != nil
            if headers || hasDynamicHeader {
                section.boundarySupplementaryItems = [.init(
                    layoutSize: .init(
                        widthDimension: .fractionalWidth(1),
                        heightDimension: .absolute(40)
                    ),
                    elementKind: UICollectionView.elementKindSectionHeader,
                    alignment: .top
                )]
            }
            return section
        }
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        window.rootViewController = controller
        collectionView = RecordingCollectionView(frame: window.bounds, collectionViewLayout: layout)
        collectionView.selfSizingInvalidation = .enabledIncludingConstraints
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.addSubview(collectionView)
        orchestrator = backend.orchestrator(for: collectionView, diffAlgorithm: diffAlgorithm)
        lookup.owner = orchestrator
        window.isHidden = false
        window.layoutIfNeeded()
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
    }
}

@MainActor
private final class LayoutLookup {
    weak var owner: CollectionOrchestrator?
}

@MainActor
private final class RecordingCollectionView: UICollectionView {
    var batches = 0
    var reloads = 0
    var reconfigured: [IndexPath] = []
    var replaced: [IndexPath] = []
    var sectionReloads = IndexSet()
    var movedItems: [(from: IndexPath, to: IndexPath)] = []
    var activeBatches = 0
    var maximumActiveBatches = 0

    func resetCounts() {
        batches = 0
        reloads = 0
        reconfigured = []
        replaced = []
        sectionReloads = []
        movedItems = []
    }

    override func moveItem(at indexPath: IndexPath, to newIndexPath: IndexPath) {
        movedItems.append((from: indexPath, to: newIndexPath))
        super.moveItem(at: indexPath, to: newIndexPath)
    }

    override func reloadData() {
        reloads += 1
        super.reloadData()
    }

    override func reloadItems(at indexPaths: [IndexPath]) {
        replaced += indexPaths
        super.reloadItems(at: indexPaths)
    }

    override func reloadSections(_ sections: IndexSet) {
        sectionReloads.formUnion(sections)
        super.reloadSections(sections)
    }

    override func reconfigureItems(at indexPaths: [IndexPath]) {
        reconfigured += indexPaths
        super.reconfigureItems(at: indexPaths)
    }

    override func performBatchUpdates(
        _ updates: (() -> Void)?,
        completion: ((Bool) -> Void)? = nil
    ) {
        batches += 1
        activeBatches += 1
        maximumActiveBatches = max(maximumActiveBatches, activeBatches)
        super.performBatchUpdates(updates) { [self] finished in
            activeBatches -= 1
            completion?(finished)
        }
    }
}


enum CollectionBackend: CaseIterable, Sendable {
    case manual, native

    @MainActor
    func orchestrator(
        for view: UICollectionView,
        diffAlgorithm: any SectionedDiffAlgorithm = SectionedDiff()
    ) -> CollectionOrchestrator {
        switch self {
        case .manual:
            CollectionOrchestrator(collectionView: view, diffAlgorithm: diffAlgorithm)
        case .native:
            CollectionOrchestrator(collectionView: view) { view, cell, supplementary in
                DiffableCollectionDataSource(
                    collectionView: view, cellProvider: cell, supplementaryProvider: supplementary
                )
            }
        }
    }
}
