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
        let owner = CollectionOrchestrator(collectionView: fixture.view) { view, cell, supplementary in
            factories += 1
            let source = ExternalDataSource(view: view, cell: cell, supplementary: supplementary, probe: probe)
            probe.source = source
            return source
        }
        var completed: [Int] = []
        await withCheckedContinuation { started in
            probe.didStart = { started.resume() }
            owner.apply([PublicSection("first", [1])], animated: false) { _ in completed.append(1) }
        }
        #expect(owner.isApplying)
        #expect(owner.appliedRevision == 0)
        #expect(owner.sectionIds.isEmpty)
        #expect(owner.cellPresenter(at: .init(item: 0, section: 0)) == nil)
        #expect(completed.isEmpty)

        await withCheckedContinuation { finished in
            owner.apply([PublicSection("second", [2, 3])], animated: false) { _ in
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
        weak var retained: (any CollectionDataSource)?
        var factories = 0
        var owner: CollectionOrchestrator? = CollectionOrchestrator(collectionView: fixture.view) {
            view, cell, supplementary in
            factories += 1
            let source: any CollectionDataSource
            if native {
                source = DiffableCollectionDataSource(
                    collectionView: view, cellProvider: cell, supplementaryProvider: supplementary
                )
            } else {
                source = DefaultCollectionDataSource(
                    collectionView: view, cellProvider: cell, supplementaryProvider: supplementary
                )
            }
            retained = source
            return source
        }
        try await owner?.apply([PublicSection("s", [1, 2])], animated: false)
        try await owner?.apply([PublicSection("s", [2, 1])], animated: false)
        #expect(owner?.indexPath(for: PublicID(1)) == .init(item: 1, section: 0))
        try await owner?.apply([], animated: false)
        #expect(owner?.indexPath(for: PublicID(1)) == nil)
        try await owner?.apply([PublicSection("s", [1])], animated: false)
        #expect(owner?.indexPath(for: PublicID(1)) == .init(item: 0, section: 0))
        try await owner?.apply([PublicSection("reloaded", [2])], animated: false, mode: .reload)
        #expect(owner?.indexPath(for: PublicID(1)) == nil)
        #expect(owner?.indexPath(for: PublicID(2)) == .init(item: 0, section: 0))
        #expect(owner?.sectionIndex(for: "s") == nil)
        #expect(owner?.sectionIndex(for: "reloaded") == 0)
        #expect(owner?.sectionId(at: -1) == nil)
        #expect(owner?.sectionId(at: 50) == nil)
        #expect(owner?.cellPresenter(at: .init(item: 50, section: 0)) == nil)
        #expect(factories == 1)
        #expect(retained != nil)
        owner = nil
        #expect(retained == nil)
    }
}

@MainActor
private final class SourceProbe {
    weak var source: ExternalDataSource?
    var inputs: [(source: [AnyHashable], target: [AnyHashable])] = []
    var didStart: (() -> Void)?
    var release: CheckedContinuation<Void, Never>?
}

/// This implementation knows nothing about Parade's planner, registry or bridge.
@MainActor
private final class ExternalDataSource: NSObject, CollectionDataSource, UICollectionViewDataSource {
    let view: UICollectionView
    let cell: CollectionCellProvider
    let supplementary: CollectionSupplementaryProvider
    let probe: SourceProbe
    var content = CollectionComposition.empty

    init(
        view: UICollectionView,
        cell: @escaping CollectionCellProvider,
        supplementary: @escaping CollectionSupplementaryProvider,
        probe: SourceProbe
    ) {
        self.view = view
        self.cell = cell
        self.supplementary = supplementary
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

    func apply(
        from source: CollectionComposition,
        to target: CollectionComposition,
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
        content = target
        view.reloadData()
        view.layoutIfNeeded()
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
        cell(collectionView, indexPath, cellPresenter(at: indexPath))
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        supplementary(collectionView, kind, indexPath, supplementaryPresenter(ofKind: kind, at: indexPath))
    }
}

private final class PublicID: Hashable {
    let value: Int
    init(_ value: Int) { self.value = value }
    static func == (lhs: PublicID, rhs: PublicID) -> Bool { lhs.value == rhs.value }
    func hash(into hasher: inout Hasher) { hasher.combine(value) }
}

private struct PublicSection: SectionPresenter {
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
