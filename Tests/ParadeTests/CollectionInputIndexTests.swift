// Created by weixi on 2026/09/17.

import Testing
import UIKit
@testable import Parade

struct CollectionInputIndexTests {
    @Test("Captured lookup values preserve section order and their original presenters")
    func lookupValues() throws {
        let sections = [section("b", cells: [2]), section("a", cells: [1, 3])]
        let composition = try CollectionComposition(sections)

        #expect(composition.sections.map(\.id) == [AnyHashable("b"), AnyHashable("a")])
        #expect(composition.sectionsById["a"]?.cells == sections[1].cells)
        #expect(composition.cellsById[3] == sections[1].cells[1])
        #expect(composition.sectionsById.count == 2)
        #expect(composition.cellsById.count == 3)
        let empty = try CollectionComposition([])
        #expect(empty.sections.isEmpty && empty.sectionsById.isEmpty && empty.cellsById.isEmpty)
    }

    @Test("Supplementary identities are scoped to section and kind")
    @MainActor
    func supplementaryScopes() throws {
        let composition = try CollectionComposition([
            section("a", views: [view("shared", kind: "header"), view("shared", kind: "footer")]),
            section("b", views: [view("shared", kind: "header")])
        ])
        #expect(composition.sections.map { $0.supplementaryViews.count } == [2, 1])
    }

    enum InvalidInput: CaseIterable, Sendable {
        case duplicateSection, duplicateCell, duplicateAddress, duplicateSupplementary
        case emptyKind, negativeItem, cellBeforeLaterSection, supplementaryBeforeLaterCell
        case sectionBeforeItsCells, cellBeforeSupplementary, addressBeforeIdentity
    }

    @Test(
        "Rejected input retains its first error and both conflict positions",
        arguments: InvalidInput.allCases
    )
    @MainActor
    func rejection(input: InvalidInput) {
        let (sections, expected, locations) = invalidInput(input)
        do {
            _ = try CollectionComposition(sections)
            Issue.record("Expected invalid input rejection")
        } catch {
            #expect(error.error == expected)
            #expect(error.diagnostic.reason == .invalidUpdate(expected))
            #expect(error.diagnostic.locations == locations)
            #expect(error.diagnostic.recovery == .rejectedUpdate)
        }
    }

    @MainActor
    private func invalidInput(_ input: InvalidInput) -> (
        [SectionContent], CollectionUpdateError, [CollectionDiagnostic.Location]
    ) {
        switch input {
        case .duplicateSection:
            return (
                [section("a"), section("a")], .duplicateSectionId("a"),
                [.init(section: 0), .init(section: 1)]
            )
        case .duplicateCell:
            return (
                [section("a", cells: [1, 2]), section("b", cells: [2])], .duplicateCellId("2"),
                [.init(section: 0, item: 1), .init(section: 1, item: 0)]
            )
        case .duplicateAddress:
            return (
                [section("a", views: [view("first"), view("second")])],
                .duplicateSupplementaryPlacement(section: "a", kind: "header", item: 0),
                [.init(section: 0, item: 0), .init(section: 0, item: 0)]
            )
        case .duplicateSupplementary:
            return (
                [section("a", views: [view("same", item: 2), view("same", item: 5)])],
                .duplicateSupplementaryId(section: "a", kind: "header", id: "same"),
                [.init(section: 0, item: 2), .init(section: 0, item: 5)]
            )
        case .emptyKind:
            return (
                [section("a", views: [view("invalid", kind: "")])],
                .invalidSupplementaryPlacement(section: "a", kind: "", item: 0),
                [.init(section: 0, item: 0)]
            )
        case .negativeItem:
            return (
                [section("a", views: [view("invalid", item: -1)])],
                .invalidSupplementaryPlacement(section: "a", kind: "header", item: -1),
                [.init(section: 0, item: -1)]
            )
        case .cellBeforeLaterSection:
            return (
                [section("a", cells: [1, 1]), section("a")], .duplicateCellId("1"),
                [.init(section: 0, item: 0), .init(section: 0, item: 1)]
            )
        case .supplementaryBeforeLaterCell:
            return (
                [section("a", views: [view("invalid", item: -1)]), section("b", cells: [1, 1])],
                .invalidSupplementaryPlacement(section: "a", kind: "header", item: -1),
                [.init(section: 0, item: -1)]
            )
        case .sectionBeforeItsCells:
            return (
                [section("a", cells: [1]), section("a", cells: [1])], .duplicateSectionId("a"),
                [.init(section: 0), .init(section: 1)]
            )
        case .cellBeforeSupplementary:
            return (
                [section("a", cells: [1, 1], views: [view("invalid", item: -1)])],
                .duplicateCellId("1"), [.init(section: 0, item: 0), .init(section: 0, item: 1)]
            )
        case .addressBeforeIdentity:
            return (
                [section("a", views: [view("same"), view("same")])],
                .duplicateSupplementaryPlacement(section: "a", kind: "header", item: 0),
                [.init(section: 0, item: 0), .init(section: 0, item: 0)]
            )
        }
    }

    private func section(
        _ id: String,
        cells: [Int] = [],
        views: [AnySupplementaryPresenter] = []
    ) -> SectionContent {
        SectionContent(
            id: AnyHashable(id),
            cells: cells.map { AnyCellPresenter(IndexedCell(id: $0)) },
            supplementaryViews: views
        )
    }

    @MainActor
    private func view(
        _ id: String,
        kind: String = "header",
        item: Int = 0
    ) -> AnySupplementaryPresenter {
        AnySupplementaryPresenter(IndexedSupplementary(id: id, elementKind: kind, itemIndex: item))
    }
}

private struct IndexedCell: CellPresenter {
    let id: Int
    func configure(_ cell: UICollectionViewCell) {}
}

private struct IndexedSupplementary: SupplementaryPresenter {
    let id: String
    let elementKind: String
    let itemIndex: Int
    func configure(_ view: UICollectionReusableView) {}
}
