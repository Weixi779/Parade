// Created by weixi on 2026/09/17.

import Testing
import UIKit
@testable import Parade

@Suite("Complete collection planning")
struct CollectionUpdatePlannerTests {
    @Test("A separate actor can construct, compare, validate and diff local presentation values")
    func planningOutsideMainActor() async throws {
        let result = try await PlanningContext().plan()
        #expect(result.equalValues)
        #expect(result.stageCount == 1)
        #expect(result.insertedItem == 0)
        #expect(result.reconfiguredItem == 1)
    }

    @Test("Every structural stage carries source content until the final content phase")
    @MainActor
    func stageContentAndFinalCoordinates() throws {
        let source = try composition([
            section("a", [cell(1, "one"), cell(2, "old two")], header: header("old header")),
            section("removed", [cell(3, "old three")])
        ])
        let target = try composition([
            section("new", [cell(3, "new three"), cell(4, "four")], header: header("new section")),
            section("a", [cell(2, "new two"), cell(1, "one")], header: header("new header"))
        ])
        let changeset = try CollectionUpdatePlanner().changeset(from: source, to: target)

        #expect(changeset.stages.count == 3)
        for stage in changeset.stages {
            #expect(stage.sections.map(\.structure) == stage.structure.sections)
            for section in stage.sections {
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
        #expect(changeset.target.structure == target.structure)
        #expect(changeset.target.cellsById[3] == cell(3, "new three"))
        #expect(changeset.content.reconfiguredCells == [path(0, 0), path(1, 0)])
        #expect(changeset.content.replacedCells.isEmpty)
        #expect(changeset.content.reloadedSections.isEmpty)
        #expect(changeset.supplementaryUpdates.map(\.indexPath) == [path(1, 0)])
        #expect(changeset.supplementaryUpdates.first?.presenter ==
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
        let changeset = try CollectionUpdatePlanner().changeset(from: source, to: target)

        #expect(changeset.stages.isEmpty)
        #expect(changeset.content.reloadedSections == IndexSet(integer: 0))
        #expect(changeset.content.replacedCells == [path(1, 0)])
        #expect(changeset.content.reconfiguredCells == [path(1, 1)])
        #expect(changeset.supplementaryUpdates.isEmpty)
    }

    @Test("An equal-content plan still supplies the target's new behavior")
    @MainActor
    func equalContentKeepsTargetBehavior() throws {
        var actions: [Int] = []
        let first = AnyCellPresenter(ActionCell(
            id: 1,
            title: "same",
            action: { actions.append(1) }
        ))
        let next = AnyCellPresenter(ActionCell(id: 1, title: "same", action: { actions.append(2) }))
        let source = try composition([section("s", [first])])
        let target = try composition([section("s", [next])])
        let changeset = try CollectionUpdatePlanner().changeset(from: source, to: target)

        #expect(first == next)
        #expect(changeset.stages.isEmpty)
        #expect(changeset.content.isEmpty)
        #expect(changeset.supplementaryUpdates.isEmpty)
        let presenter =
            try #require(changeset.target.cellsById[1]?.underlyingPresenter as? ActionCell)
        presenter.action()
        #expect(actions == [2])
    }

    @Test("The same planner plans independent baselines without retaining an earlier target")
    func independentBaselines() throws {
        let planner = CollectionUpdatePlanner()
        let first = try composition([section("first", [cell(1, "first")])])
        let second = try composition([section("second", [cell(2, "second")])])
        _ = try planner.changeset(from: .empty, to: first)
        let changeset = try planner.changeset(from: .empty, to: second)

        #expect(changeset.stages.count == 1)
        #expect(changeset.stages.first?.structure.insertedSections == IndexSet(integer: 0))
        #expect(changeset.stages.first?.sections.map(\.id) == [AnyHashable("second")])
        #expect(changeset.target.cellsById[1] == nil)
        #expect(changeset.content.isEmpty)
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
        equalValues: Bool, stageCount: Int, insertedItem: Int?, reconfiguredItem: Int?
    ) {
        let old = AnyCellPresenter(ValueCell(id: 1, title: "old"))
        let same = AnyCellPresenter(ValueCell(id: 1, title: "old"))
        let source = try CollectionComposition([SectionContent(id: "section", cells: [old])])
        let target = try CollectionComposition([SectionContent(id: "section", cells: [
            AnyCellPresenter(ValueCell(id: 2, title: "inserted")),
            AnyCellPresenter(ValueCell(id: 1, title: "updated"))
        ])])
        let changeset = try CollectionUpdatePlanner().changeset(from: source, to: target)
        return (
            old == same,
            changeset.stages.count,
            changeset.stages.first?.structure.insertedItems.first?.item,
            changeset.content.reconfiguredCells.first?.item
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
