// Created by weixi on 2026/09/17.

import Testing
import UIKit
@testable import Parade

@Suite("Complete collection planning")
struct CollectionUpdatePlanTests {
    @Test("A separate actor can construct, compare, validate and diff local presentation values")
    func planningOutsideMainActor() async throws {
        let result = try await PlanningContext().plan()
        #expect(result.equalValues)
        #expect(result.batchCount == 1)
        #expect(result.insertedItem == 0)
        #expect(result.reconfiguredItem == 1)
    }

    @Test("Every structural batch carries source content until the final content phase")
    @MainActor
    func batchContentAndFinalCoordinates() throws {
        let source = try composition([
            section("a", [cell(1, "one"), cell(2, "old two")], header: header("old header")),
            section("removed", [cell(3, "old three")])
        ])
        let target = try composition([
            section("new", [cell(3, "new three"), cell(4, "four")], header: header("new section")),
            section("a", [cell(2, "new two"), cell(1, "one")], header: header("new header"))
        ])
        let plan = try CollectionUpdatePlan(from: source, to: target)

        #expect(plan.batches.count == 3)
        for batch in plan.batches {
            for section in batch.sections {
                let metadata =
                    try #require(source.sectionsById[section.id] ?? target.sectionsById[section.id])
                #expect(section.supplementaryViews == metadata.supplementaryViews)
                for presenter in section.cells {
                    let expected =
                        try #require(source.cellsById[presenter.id] ??
                            target.cellsById[presenter.id])
                    #expect(presenter == expected)
                }
            }
        }
        #expect(plan.content.reconfiguredCells == [path(0, 0), path(1, 0)])
        #expect(plan.content.replacedCells.isEmpty)
        #expect(plan.content.reloadedSections.isEmpty)
        #expect(plan.content.supplementaryUpdates.map(\.indexPath) == [path(1, 0)])
        #expect(plan.content.supplementaryUpdates.first?.presenter ==
            target.sections[1].supplementaryViews.first)
    }

    @Test(
        "Section reloads subsume cell edits while other sections distinguish replacement from reconfiguration"
    )
    @MainActor
    func contentEditPrecedence() throws {
        let source = try composition([
            section("a", [cell(1, "old")], header: header("header")),
            section("b", [cell(2, "old"), cell(3, "old")])
        ])
        let target = try composition([
            section("a", [AnyCellPresenter(AlternateCell(id: 1))]),
            section("b", [AnyCellPresenter(AlternateCell(id: 2)), cell(3, "new")])
        ])
        let plan = try CollectionUpdatePlan(from: source, to: target)

        #expect(plan.batches.isEmpty)
        #expect(plan.content.reloadedSections == IndexSet(integer: 0))
        #expect(plan.content.replacedCells == [path(1, 0)])
        #expect(plan.content.reconfiguredCells == [path(1, 1)])
        #expect(plan.content.supplementaryUpdates.isEmpty)
    }

    @Test("Changed actions with equal content require no view operations")
    @MainActor
    func equalContentNeedsNoViewOperations() throws {
        var actions: [Int] = []
        let first = AnyCellPresenter(ActionCell(
            id: 1,
            title: "same",
            action: { actions.append(1) }
        ))
        let next = AnyCellPresenter(ActionCell(id: 1, title: "same", action: { actions.append(2) }))
        let source = try composition([section("s", [first])])
        let target = try composition([section("s", [next])])
        let plan = try CollectionUpdatePlan(from: source, to: target)

        #expect(first == next)
        #expect(plan.batches.isEmpty)
        #expect(plan.content.isEmpty)
        #expect(plan.content.supplementaryUpdates.isEmpty)
        #expect(actions.isEmpty)
    }

    @Test("Separate update plans use only their supplied baseline")
    func independentBaselines() throws {
        let first = try composition([section("first", [cell(1, "first")])])
        let second = try composition([section("second", [cell(2, "second")])])
        _ = try CollectionUpdatePlan(from: .empty, to: first)
        let plan = try CollectionUpdatePlan(from: .empty, to: second)

        #expect(plan.batches.count == 1)
        #expect(plan.batches.first?.insertedSections == IndexSet(integer: 0))
        #expect(plan.batches.first?.sections.map(\.id) == [AnyHashable("second")])
        #expect(plan.batches.flatMap(\.sections).flatMap(\.cells).map(\.id) == [AnyHashable(2)])
        #expect(plan.content.isEmpty)
    }

    @Test("Invalid captured input retains both conflict locations")
    func validationLocations() {
        do {
            _ = try composition([
                section("a", [cell(1, "first")]),
                section("b", [cell(1, "second")])
            ])
            Issue.record("Expected duplicate occurrence rejection")
        } catch {
            #expect(error.error == .duplicateCellId("1"))
            #expect(error.diagnostic.locations == [
                .init(section: 0, item: 0),
                .init(section: 1, item: 0)
            ])
            #expect(error.diagnostic.recovery == .rejectedUpdate)
        }
    }

    private func composition(
        _ sections: [SectionContent]
    ) throws(CollectionComposition.ValidationFailure) -> CollectionComposition {
        try CollectionComposition(sections)
    }

    private func section(
        _ id: String,
        _ cells: [AnyCellPresenter],
        header: AnySupplementaryPresenter? = nil
    ) -> SectionContent {
        SectionContent(
            id: AnyHashable(id),
            cells: cells,
            supplementaryViews: header.map { [$0] } ?? []
        )
    }

    private func cell(_ id: Int, _ title: String) -> AnyCellPresenter {
        AnyCellPresenter(ValueCell(id: id, title: title))
    }

    @MainActor
    private func header(_ title: String) -> AnySupplementaryPresenter {
        AnySupplementaryPresenter(Header(title: title))
    }

    private func path(_ section: Int, _ item: Int) -> IndexPath {
        IndexPath(item: item, section: section)
    }
}

// Constructs all presentation values locally; only scalar results cross actors.
private actor PlanningContext {
    func plan() throws -> (
        equalValues: Bool, batchCount: Int, insertedItem: Int?, reconfiguredItem: Int?
    ) {
        let old = AnyCellPresenter(ValueCell(id: 1, title: "old"))
        let same = AnyCellPresenter(ValueCell(id: 1, title: "old"))
        let source = try CollectionComposition([SectionContent(id: "section", cells: [old])])
        let target = try CollectionComposition([SectionContent(id: "section", cells: [
            AnyCellPresenter(ValueCell(id: 2, title: "inserted")),
            AnyCellPresenter(ValueCell(id: 1, title: "updated"))
        ])])
        let plan = try CollectionUpdatePlan(from: source, to: target)
        return (
            old == same,
            plan.batches.count,
            plan.batches.first?.insertedItems.first?.item,
            plan.content.reconfiguredCells.first?.item
        )
    }
}

// These presenters exercise inherited, synthesized Equatable through erasure.
private struct ValueCell: CellPresenter {
    let id: Int
    let title: String
    func configure(_ cell: UICollectionViewCell) {}
}

private struct AlternateCell: CellPresenter {
    let id: Int
    func configure(_ cell: UICollectionViewListCell) {}
}

private struct Header: SupplementaryPresenter {
    let id = "header"
    let title: String
    var elementKind: String { Self.headerKind }
    func configure(_ view: UICollectionReusableView) {}
}

private struct ActionCell: CellPresenter {
    let id: Int
    let title: String
    let action: @MainActor () -> Void
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title
    }

    func configure(_ cell: UICollectionViewCell) {}
}
