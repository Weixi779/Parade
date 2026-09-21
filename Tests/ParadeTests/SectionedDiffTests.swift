// Created by weixi on 2026/09/17.

import Foundation
import Parade
import Testing

@Suite("Public sectioned diff contract")
struct SectionedDiffTests {
    @Test("The public algorithm rejects duplicate identities before producing changes", arguments: [
        DiffInputError.Input.source, .target
    ])
    func duplicateIdentities(input: DiffInputError.Input) {
        let duplicateSections = [ValueSection(id: "s"), ValueSection(id: "s")]
        let duplicateItems = [
            ValueSection(id: "a", items: [.init(id: 1)]),
            ValueSection(id: "b", items: [.init(id: 1)])
        ]
        #expect(throws: DiffInputError.duplicateSectionId(
            "s", input: input, first: 0, duplicate: 1
        )) {
            _ = try SectionedDiff().diff(
                from: input == .source ? duplicateSections : [],
                to: input == .target ? duplicateSections : []
            )
        }
        #expect(throws: DiffInputError.duplicateItemId(
            "1", input: input,
            first: .init(section: 0, item: 0), duplicate: .init(section: 1, item: 0)
        )) {
            _ = try SectionedDiff().diff(
                from: input == .source ? duplicateItems : [],
                to: input == .target ? duplicateItems : []
            )
        }
    }

    @Test("Section content and item content are independent, even with unchanged identities")
    func contentBoundaries() throws {
        let source = [ValueSection(id: "a", title: "header", items: [.init(id: 1, text: "old")])]
        let itemTarget = [ValueSection(
            id: "a",
            title: "header",
            items: [.init(id: 1, text: "new")]
        )]
        let sectionTarget = [ValueSection(id: "a", title: "changed", items: source[0].items)]
        for algorithm in algorithms {
            let items = try algorithm.diff(from: source, to: itemTarget)
            #expect(items.updatedSections.isEmpty)
            #expect(items.updatedItems == [.init(section: 0, item: 0)])
            #expect(items.movedItems.isEmpty)
            let sections = try algorithm.diff(from: source, to: sectionTarget)
            #expect(sections.updatedSections == [0])
            #expect(sections.updatedItems.isEmpty)
            #expect(try algorithm.diff(from: source, to: source).isEmpty)
        }
    }

    @Test("A transfer from a deleted section to a new section retains identity and content updates")
    func transferAndUpdate() throws {
        let source = [ValueSection(id: "old", items: [.init(id: 1, text: "old"), .init(id: 2)])]
        let target = [ValueSection(id: "new", items: [.init(id: 3), .init(id: 1, text: "new")])]
        for algorithm in algorithms {
            let result = try algorithm.diff(from: source, to: target)
            #expect(result.deletedSections == [0])
            #expect(result.insertedSections == [0])
            #expect(result.deletedItems == [.init(section: 0, item: 1)])
            #expect(result.insertedItems == [.init(section: 0, item: 0)])
            #expect(result.movedItems.count == 1)
            #expect(result.movedItems.first?.from == .init(section: 0, item: 0))
            #expect(result.movedItems.first?.to == .init(section: 0, item: 1))
            #expect(result.updatedItems == [.init(section: 0, item: 1)])
            #expect(result.updatedSections.isEmpty)
        }
    }

    @Test("Moving a section carries its unchanged items without marking item moves")
    func sectionMovesCarryItems() throws {
        let source = [
            ValueSection(id: "a", items: [.init(id: 1)]),
            ValueSection(id: "b", items: [.init(id: 2)])
        ]
        for algorithm in algorithms {
            let result = try algorithm.diff(from: source, to: source.reversed())
            #expect(result.movedSections.count == 1)
            #expect(result.movedItems.isEmpty)
            #expect(result.updatedItems.isEmpty)
        }
    }

    @Test("Algorithms can choose different valid moves for the same input")
    func differentMovePolicies() throws {
        let source = [ValueSection(id: "s", items: (0..<4).map { ValueItem(id: $0) })]
        let target = [ValueSection(id: "s", items: [1, 2, 3, 0].map { ValueItem(id: $0) })]
        let greedy = try SectionedDiff().diff(from: source, to: target)
        let alternative = try StandardLibraryDiff().diff(from: source, to: target)
        #expect(greedy.movedItems.count == 3)
        #expect(alternative.movedItems.count == 1)
        #expect(alternative.movedItems.first?.from == .init(section: 0, item: 0))
        #expect(alternative.movedItems.first?.to == .init(section: 0, item: 3))
    }

    @Test("Empty sections can update their own content")
    func emptyCapturedSection() throws {
        for algorithm in algorithms {
            let result = try algorithm.diff(
                from: [ValueSection(id: "s", title: "old")],
                to: [ValueSection(id: "s", title: "new")]
            )
            #expect(result.updatedSections == [0])
            #expect(result.updatedItems.isEmpty)
            #expect(result.insertedSections.isEmpty)
        }
    }

    private var algorithms: [any SectionedDiffAlgorithm] { [SectionedDiff(), StandardLibraryDiff()]
    }
}

private struct ValueItem: DiffableElement {
    let id: Int
    var text = ""
}

private struct ValueSection: DiffableSection {
    let id: String
    var title = ""
    var items: [ValueItem] = []
    func isContentEqual(to other: Self) -> Bool { title == other.title }
}
