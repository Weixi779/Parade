// Created by weixi on 2026/09/17.

import Parade
import Testing
import UIKit

/// Intentionally uses only the public module, including an independent implementation.
@MainActor
@Suite("Data source injection")
struct CollectionDataSourceTests {
    @Test("An external implementation owns current queries and completion gates the queue")
    func externalImplementation() async throws {
        let fixture = PublicFixture()
        defer { fixture.window.isHidden = true }
        let probe = SourceProbe()
        var factories = 0
        let owner = CollectionOrchestrator<CompositionalSectionLayout>(collectionView: fixture.view) { view, views in
            factories += 1
            let source = ExternalDataSource(view: view, views: views, probe: probe)
            probe.source = source
            return source
        }
        var completed: [Int] = []
        await withCheckedContinuation { started in
            probe.didStart = { started.resume() }
            owner.compose([PublicSection("first", [1])]).apply(animated: false) { _ in completed.append(1) }
        }
        #expect(owner.isApplying)
        #expect(owner.appliedRevision == 0)
        #expect(owner.sectionIds.isEmpty)
        #expect(owner.cellPresenter(at: .init(item: 0, section: 0)) == nil)
        #expect(completed.isEmpty)

        await withCheckedContinuation { finished in
            owner.compose([PublicSection("second", [2, 3])]).apply(animated: false) { _ in
                completed.append(2)
                finished.resume()
            }
            #expect(probe.inputs.count == 1)
            probe.release?.resume()
            probe.release = nil
        }
        #expect(factories == 1)
        #expect(completed == [1, 2])
        #expect(probe.inputs.map(\.source) == [[], [AnyHashable("first")]])
        #expect(probe.inputs.map(\.target) == [[AnyHashable("first")], [AnyHashable("second")]])
        #expect(owner.sectionId(at: 0) == AnyHashable("second"))
        #expect(owner.indexPath(for: PublicID(3)) == .init(item: 1, section: 0))
        #expect(owner.cellPresenter(for: PublicID(3))?.id == AnyHashable(PublicID(3)))
        #expect(owner.appliedRevision == 2)
        #expect(!owner.isApplying)
        let cell = try #require(fixture.view.cellForItem(at: .init(item: 1, section: 0)) as? PublicCell)
        #expect(cell.accessibilityLabel == "3")
        #expect(fixture.view.dataSource === probe.source)
    }

    @Test("Both built-in factories preserve non-Sendable IDs and release their instance", arguments: [false, true])
    func identityAndLifetime(native: Bool) async throws {
        let fixture = PublicFixture()
        defer { fixture.window.isHidden = true }
        weak var retained: (any CollectionDataSource<CompositionalSectionLayout>)?
        weak var retainedViews: CollectionViews?
        var factories = 0
        var owner: CollectionOrchestrator<CompositionalSectionLayout>? = CollectionOrchestrator<CompositionalSectionLayout>(collectionView: fixture.view) {
            view, views in
            factories += 1
            retainedViews = views
            let source: any CollectionDataSource<CompositionalSectionLayout>
            if native {
                source = DiffableCollectionDataSource<CompositionalSectionLayout>(
                    collectionView: view,
                    views: views
                )
            } else {
                source = StagedCollectionDataSource<CompositionalSectionLayout>(
                    collectionView: view,
                    views: views
                )
            }
            retained = source
            return source
        }
        try await owner?.compose([PublicSection("s", [1, 2])]).apply(animated: false)
        try await owner?.compose([PublicSection("s", [2, 1])]).apply(animated: false)
        #expect(owner?.indexPath(for: PublicID(1)) == .init(item: 1, section: 0))
        try await owner?.compose([]).apply(animated: false)
        #expect(owner?.indexPath(for: PublicID(1)) == nil)
        try await owner?.compose([PublicSection("s", [1])]).apply(animated: false)
        #expect(owner?.indexPath(for: PublicID(1)) == .init(item: 0, section: 0))
        try await owner?.compose([PublicSection("reloaded", [2])]).apply(animated: false, mode: .reload)
        #expect(owner?.indexPath(for: PublicID(1)) == nil)
        #expect(owner?.indexPath(for: PublicID(2)) == .init(item: 0, section: 0))
        #expect(owner?.sectionIndex(for: "s") == nil)
        #expect(owner?.sectionIndex(for: "reloaded") == 0)
        #expect(owner?.sectionId(at: -1) == nil)
        #expect(owner?.sectionId(at: 50) == nil)
        #expect(owner?.cellPresenter(at: .init(item: 50, section: 0)) == nil)
        #expect(factories == 1)
        #expect(retained != nil)
        #expect(retainedViews != nil)
        owner = nil
        #expect(retained == nil)
        #expect(retainedViews == nil)
    }

    @Test("An external source refreshes content and bindings while retaining compatible views")
    func externalContentUpdates() async throws {
        let fixture = PublicFixture()
        defer { fixture.window.isHidden = true }
        let probe = SourceProbe()
        weak var retainedViews: CollectionViews?
        var owner: CollectionOrchestrator<CompositionalSectionLayout>? = CollectionOrchestrator(
            collectionView: fixture.view
        ) { view, views in
            retainedViews = views
            let source = ExternalDataSource(view: view, views: views, probe: probe)
            probe.source = source
            return source
        }
        let section = EditableSection()
        var actions: [String] = []
        section.cells = [AnyCellPresenter(EditableCellPresenter(text: "old") { actions.append("old cell") })]
        section.headers = [AnySupplementaryPresenter(EditableHeaderPresenter(text: "old") {
            actions.append("old header")
        })]
        try await owner?.compose([section]).apply(animated: false)
        let path = IndexPath(item: 0, section: 0)
        let cell = try #require(fixture.view.cellForItem(at: path) as? EditableCell)
        let header = try #require(fixture.view.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader,
            at: path
        ) as? EditableHeader)

        section.cells = [AnyCellPresenter(EditableCellPresenter(text: "new") { actions.append("new cell") })]
        section.headers = [AnySupplementaryPresenter(EditableHeaderPresenter(text: "new") {
            actions.append("new header")
        })]
        section.height = 72
        try await section.update(animated: false)
        #expect(fixture.view.cellForItem(at: path) === cell)
        #expect(fixture.view.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader,
            at: path
        ) === header)
        #expect(cell.accessibilityLabel == "new")
        #expect(header.accessibilityLabel == "new")
        #expect(abs(cell.frame.height - 72) < 0.1)
        cell.action?()
        header.action?()
        #expect(actions == ["new cell", "new header"])

        let cellConfigurations = cell.configurations
        let headerConfigurations = header.configurations
        section.cells = [AnyCellPresenter(EditableCellPresenter(text: "new") { actions.append("latest cell") })]
        section.headers = [AnySupplementaryPresenter(EditableHeaderPresenter(text: "new") {
            actions.append("latest header")
        })]
        try await section.update(animated: false)
        cell.action?()
        header.action?()
        #expect(actions.suffix(2) == ["latest cell", "latest header"])
        #expect(cell.configurations == cellConfigurations)
        #expect(header.configurations == headerConfigurations)

        section.height = 110
        try await section.update(animated: false)
        #expect(abs(cell.frame.height - 110) < 0.1)
        #expect(cell.configurations == cellConfigurations)
        #expect(header.configurations == headerConfigurations)
        #expect(probe.reloads == 1)
        #expect(owner?.appliedRevision == 4)
        #expect(retainedViews != nil)
        owner = nil
        #expect(probe.source == nil)
        #expect(retainedViews == nil)
    }

    @Test("An external source replaces incompatible cells and supplementary views")
    func externalViewReplacement() async throws {
        let fixture = PublicFixture()
        defer { fixture.window.isHidden = true }
        let probe = SourceProbe()
        let owner = CollectionOrchestrator<CompositionalSectionLayout>(collectionView: fixture.view) { view, views in
            ExternalDataSource(view: view, views: views, probe: probe)
        }
        let section = EditableSection()
        section.cells = [AnyCellPresenter(EditableCellPresenter(text: "old", action: {}))]
        section.headers = [AnySupplementaryPresenter(EditableHeaderPresenter(text: "old", action: {}))]
        try await owner.compose([section]).apply(animated: false)
        let path = IndexPath(item: 0, section: 0)
        #expect(fixture.view.cellForItem(at: path) is EditableCell)
        section.cells = [AnyCellPresenter(ReplacementCellPresenter())]
        try await section.update(animated: false)
        #expect(fixture.view.cellForItem(at: path) is ReplacementCell)
        section.headers = [AnySupplementaryPresenter(ReplacementHeaderPresenter())]
        try await section.update(animated: false)
        #expect(fixture.view.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader,
            at: path
        ) is ReplacementHeader)
        #expect(probe.reloads == 1)
    }

    @Test("Public snapshot comparisons separate capture identity, content and view compatibility")
    func publicComparisons() {
        let first = AnyCellPresenter(EditableCellPresenter(text: "same", action: {}))
        let changed = AnyCellPresenter(EditableCellPresenter(text: "changed", action: {}))
        #expect(first != changed)
        #expect(first.canReuseView(with: changed))
        #expect(!first.canReuseView(with: AnyCellPresenter(ReplacementCellPresenter())))
        let header = AnySupplementaryPresenter(EditableHeaderPresenter(text: "same", action: {}))
        let changedHeader = AnySupplementaryPresenter(EditableHeaderPresenter(text: "changed", action: {}))
        #expect(header.canReuseView(with: changedHeader))
        #expect(!header.canReuseView(with: AnySupplementaryPresenter(ReplacementHeaderPresenter())))
        let original = SectionSnapshot(
            id: "section",
            cells: [first],
            supplementaryViews: [header],
            layout: { 42 }
        )
        let stage = original.replacingCells([changed])
        #expect(original.hasSameLayoutVersion(as: stage))
        #expect(original.hasSameSupplementaryContent(as: stage))
        let recaptured = SectionSnapshot(
            id: original.id,
            cells: original.cells,
            supplementaryViews: [changedHeader],
            layout: original.layoutValue
        )
        #expect(!original.hasSameLayoutVersion(as: recaptured))
        #expect(original.hasCompatibleSupplementaries(with: recaptured))
        #expect(!original.hasSameSupplementaryContent(as: recaptured))
    }
}

@MainActor
private final class SourceProbe {
    weak var source: ExternalDataSource?
    var inputs: [(source: [AnyHashable], target: [AnyHashable])] = []
    var didStart: (() -> Void)?
    var release: CheckedContinuation<Void, Never>?
    var reloads = 0
}

/// This implementation knows nothing about Parade's planner, registry or bridge.
@MainActor
private final class ExternalDataSource: NSObject, CollectionDataSource, UICollectionViewDataSource {
    let view: UICollectionView
    let views: CollectionViews
    let probe: SourceProbe
    var content = CollectionSnapshot<CompositionalSectionLayout>.empty

    init(
        view: UICollectionView,
        views: CollectionViews,
        probe: SourceProbe
    ) {
        self.view = view
        self.views = views
        self.probe = probe
    }

    var dataSource: any UICollectionViewDataSource { self }
    var sectionIds: [AnyHashable] { content.sections.map(\.id) }
    var numberOfItems: Int { content.cellsById.count }
    var isEmpty: Bool { content.sections.allSatisfy(\.isEmpty) }

    func cellPresenter(at indexPath: IndexPath) -> AnyCellPresenter? {
        guard content.sections.indices.contains(indexPath.section) else { return nil }
        return content.sections[indexPath.section].cell(at: indexPath.item)
    }

    func indexPath(for id: AnyHashable) -> IndexPath? {
        for (index, section) in content.sections.enumerated() {
            if let item = section.cells.firstIndex(where: { $0.id == id }) {
                return IndexPath(item: item, section: index)
            }
        }
        return nil
    }

    func supplementaryPresenter(ofKind kind: String, at indexPath: IndexPath) -> AnySupplementaryPresenter? {
        guard content.sections.indices.contains(indexPath.section) else { return nil }
        return content.sections[indexPath.section].supplementary(ofKind: kind, at: indexPath.item)
    }

    func sectionSnapshot(at index: Int) -> SectionSnapshot<CompositionalSectionLayout>? {
        guard content.sections.indices.contains(index) else { return nil }
        return content.sections[index]
    }

    func apply(
        from source: CollectionSnapshot<CompositionalSectionLayout>,
        to target: CollectionSnapshot<CompositionalSectionLayout>,
        animated: Bool,
        mode: CollectionUpdateMode
    ) async -> [CollectionDiagnostic] {
        probe.inputs.append((source.sections.map(\.id), target.sections.map(\.id)))
        if let started = probe.didStart {
            probe.didStart = nil
            await withCheckedContinuation { continuation in
                probe.release = continuation
                started()
            }
        }
        // This consumer deliberately reloads structural changes and performs granular
        // content updates using only the public model comparisons and view operations.
        guard mode == .diff,
              source.sections.map(\.id) == target.sections.map(\.id),
              zip(source.sections, target.sections).allSatisfy({ $0.cells.map(\.id) == $1.cells.map(\.id) }) else {
            content = target
            probe.reloads += 1
            view.collectionViewLayout.invalidateLayout()
            view.reloadData()
            view.layoutIfNeeded()
            return []
        }
        var sections = IndexSet()
        var replacements: [IndexPath] = []
        var reconfigurations: [IndexPath] = []
        var supplementaries: [(indexPath: IndexPath, presenter: AnySupplementaryPresenter)] = []
        var layoutChanged = false
        for (index, next) in target.sections.enumerated() {
            let previous = source.sections[index]
            layoutChanged = layoutChanged || !previous.hasSameLayoutVersion(as: next)
            guard previous.hasCompatibleSupplementaries(with: next) else {
                sections.insert(index)
                continue
            }
            for (item, presenter) in next.cells.enumerated() {
                let old = previous.cells[item]
                let path = IndexPath(item: item, section: index)
                if !old.canReuseView(with: presenter) { replacements.append(path) }
                else if old != presenter { reconfigurations.append(path) }
            }
            if !previous.hasSameSupplementaryContent(as: next) {
                for presenter in next.supplementaryViews where previous.supplementary(
                    ofKind: presenter.elementKind,
                    at: presenter.itemIndex
                ) != presenter {
                    supplementaries.append((IndexPath(item: presenter.itemIndex, section: index), presenter))
                }
            }
        }
        view.layoutIfNeeded()
        await withCheckedContinuation { continuation in
            let update = {
                self.view.performBatchUpdates {
                    self.content = target
                    if layoutChanged { self.view.collectionViewLayout.invalidateLayout() }
                    if !sections.isEmpty { self.view.reloadSections(sections) }
                    if !replacements.isEmpty { self.view.reloadItems(at: replacements) }
                    if !reconfigurations.isEmpty { self.view.reconfigureItems(at: reconfigurations) }
                } completion: { _ in continuation.resume() }
            }
            if animated { update() }
            else { UIView.performWithoutAnimation(update) }
        }
        views.reconfigureSupplementaries(supplementaries)
        return []
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int { content.sections.count }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        content.sections[section].cells.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        views.cell(at: indexPath, presenter: cellPresenter(at: indexPath))
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        views.supplementary(
            ofKind: kind,
            at: indexPath,
            presenter: supplementaryPresenter(ofKind: kind, at: indexPath)
        )
    }
}

private final class PublicID: Hashable {
    let value: Int
    init(_ value: Int) { self.value = value }
    static func == (lhs: PublicID, rhs: PublicID) -> Bool { lhs.value == rhs.value }
    func hash(into hasher: inout Hasher) { hasher.combine(value) }
}

@MainActor
private final class PublicSection: SectionController {
    let updateContext = SectionUpdateContext()
    func captureContent() -> LayoutContent<CompositionalSectionLayout> {
        testSectionContent(cells: cells)
    }
    let id: String
    let cells: [AnyCellPresenter]
    @MainActor
    init(_ id: String, _ items: [Int]) {
        self.id = id
        cells = items.map { AnyCellPresenter(PublicPresenter(id: PublicID($0))) }
    }
}

private struct PublicPresenter: CellPresenter {
    let id: PublicID
    func configure(_ cell: PublicCell) { cell.accessibilityLabel = String(id.value) }
}

@MainActor
private final class PublicCell: UICollectionViewCell {}

@MainActor
private final class EditableSection: SectionController {
    let id = "editable"
    let updateContext = SectionUpdateContext()
    var cells: [AnyCellPresenter] = []
    var headers: [AnySupplementaryPresenter] = []
    var height: CGFloat = 44

    func captureContent() -> LayoutContent<CompositionalSectionLayout> {
        let height = height
        return LayoutContent(cells: cells, supplementaryViews: headers) { _ in
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height))
            let item = NSCollectionLayoutItem(layoutSize: size)
            let section = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [item]))
            section.boundarySupplementaryItems = [NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(24)),
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )]
            return section
        }
    }
}

private struct EditableCellPresenter: CellPresenter {
    let id = 1
    let text: String
    let action: @MainActor () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.text == rhs.text }

    func configure(_ cell: EditableCell) {
        cell.accessibilityLabel = text
        cell.configurations += 1
    }

    func bind(to cell: EditableCell) { cell.action = action }
}

private struct EditableHeaderPresenter: SupplementaryPresenter {
    let id = "header"
    let text: String
    let action: @MainActor () -> Void
    var elementKind: String { Self.headerKind }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.text == rhs.text }

    func configure(_ view: EditableHeader) {
        view.accessibilityLabel = text
        view.configurations += 1
    }

    func bind(to view: EditableHeader) { view.action = action }
}

private struct ReplacementCellPresenter: CellPresenter {
    let id = 1
    func configure(_ cell: ReplacementCell) {}
}

private struct ReplacementHeaderPresenter: SupplementaryPresenter {
    let id = "header"
    var elementKind: String { Self.headerKind }
    func configure(_ view: ReplacementHeader) {}
}

@MainActor private final class EditableCell: UICollectionViewCell {
    var configurations = 0
    var action: (() -> Void)?
}

@MainActor private final class EditableHeader: UICollectionReusableView {
    var configurations = 0
    var action: (() -> Void)?
}

@MainActor private final class ReplacementCell: UICollectionViewCell {}
@MainActor private final class ReplacementHeader: UICollectionReusableView {}

@MainActor
private final class PublicFixture {
    let window: UIWindow
    let view: UICollectionView

    init() {
        let frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 50)
        view = UICollectionView(frame: frame, collectionViewLayout: layout)
        let controller = UIViewController()
        controller.view.addSubview(view)
        window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.isHidden = false
    }
}
