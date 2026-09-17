// Created by weixi on 2026/09/17.

import Foundation
import Testing
@testable import Parade

struct StructurePlannerTests {
    private typealias Section = SectionStructure<Int, Int>
    private typealias Stage = StructureStage<Int, Int>

    @Test("Unchanged structure emits no stages, including retained empty sections")
    func unchanged() throws {
        let sections = [Section(id: 0, items: []), Section(id: 1, items: [10, 11])]
        #expect(try plan(from: sections, to: sections).isEmpty)
        #expect(try plan(from: [Section](), to: []).isEmpty)
    }

    @Test("Insert and delete shifts do not create item or section moves")
    func membershipShifts() throws {
        let source = [Section(id: 0, items: [0, 1, 2, 3]), Section(id: 1, items: [])]
        let target = [
            Section(id: 2, items: [8]),
            Section(id: 0, items: [4, 0, 2, 5, 3]),
            Section(id: 1, items: []),
            Section(id: 3, items: [])
        ]
        let stages = try verify(from: source, to: target)
        #expect(stages.allSatisfy { $0.movedItems.isEmpty && $0.movedSections.isEmpty })
        #expect(stages.flatMap(\.deletedItems).count == 1)
        #expect(stages.flatMap(\.insertedItems).count == 2)
        #expect(stages.count == 2)
        let reverse = try verify(from: target, to: source)
        #expect(reverse.allSatisfy { $0.movedItems.isEmpty && $0.movedSections.isEmpty })
    }

    @Test("Initial population and clearing do not separately edit cells")
    func wholeSectionMembership() throws {
        let populated = [
            Section(id: 0, items: [0, 1]),
            Section(id: 1, items: []),
            Section(id: 2, items: [2])
        ]
        let inserted = try verify(from: [], to: populated)
        let removed = try verify(from: populated, to: [])
        #expect(inserted.count == 1)
        #expect(removed.count == 1)
        #expect(inserted[0].insertedSections == IndexSet(integersIn: 0..<3))
        #expect(removed[0].deletedSections == IndexSet(integersIn: 0..<3))
        #expect(inserted[0].insertedItems.isEmpty)
        #expect(removed[0].deletedItems.isEmpty)
    }

    @Test("Transfers preserve cell identity when their old and new sections are replaced")
    func transfersAcrossSectionMembership() throws {
        let source = [Section(id: 0, items: [0, 1, 2]), Section(id: 1, items: [3, 4])]
        let target = [Section(id: 2, items: [4, 0, 5]), Section(id: 1, items: [2, 3])]
        let stages = try verify(from: source, to: target)
        #expect(stages.count == 3)
        #expect(stages[0].insertedSections.count == 1)
        #expect(stages[1].movedItems.count == 3)
        #expect(stages[1].deletedItems.isEmpty)
        #expect(stages[1].insertedItems.isEmpty)
        #expect(stages[2].deletedSections.count == 1)

        var current = source
        var movedIds = Set<Int>()
        for stage in stages {
            for move in stage.movedItems {
                movedIds.insert(current[move.from.section].items[move.from.item])
            }
            current = try replay(stage, from: current)
        }
        #expect(movedIds == [0, 2, 4])
    }

    @Test("Many moves share a batch, including equal-coordinate permutation moves")
    func batchedReversal() throws {
        let source = [Section(id: 0, items: [0, 1, 2])]
        let target = [Section(id: 0, items: [2, 1, 0])]
        let stages = try verify(from: source, to: target)
        #expect(stages.count == 1)
        #expect(stages[0].movedItems.count == 2)
        #expect(stages[0].movedItems.contains { $0.from == $0.to })

        let sections = (0..<5).map { Section(id: $0, items: [$0]) }
        let reordered = try verify(from: sections, to: sections.reversed())
        #expect(reordered.count == 1)
        #expect(reordered[0].movedSections.count == 4)
        #expect(reordered[0].movedItems.isEmpty)
    }

    @Test("Duplicate IDs are rejected in either input, even on the equality fast path")
    func duplicateIdentityValidation() {
        let invalid: [[Section]] = [
            [Section(id: 0, items: []), Section(id: 0, items: [])],
            [Section(id: 0, items: [1, 1])],
            [Section(id: 0, items: [1]), Section(id: 1, items: [1])]
        ]
        for sections in invalid {
            #expect(throws: DiffInputError.self) {
                try plan(from: sections, to: [])
            }
            #expect(throws: DiffInputError.self) {
                try plan(from: [], to: sections)
            }
            #expect(throws: DiffInputError.self) {
                try plan(from: sections, to: sections)
            }
        }
    }

    @Test(
        "Identity indexing preserves error order and source/target conflict coordinates",
        arguments: [DiffInputError.Input.source, .target]
    )
    func identityErrorOrder(input: DiffInputError.Input) {
        let sectionCollision = [Section(id: 0, items: [1]), Section(id: 0, items: [1])]
        #expect(throws: DiffInputError.duplicateSectionId(
            "0", input: input, first: 0, duplicate: 1
        )) {
            _ = try DiffIndex(sectionCollision, id: { $0.id }, items: { $0.items }, input: input)
        }

        let earlierItemCollision = [Section(id: 0, items: [1, 1]), Section(id: 0, items: [])]
        #expect(throws: DiffInputError.duplicateItemId(
            "1", input: input, first: .init(section: 0, item: 0), duplicate: .init(
                section: 0,
                item: 1
            )
        )) {
            _ = try DiffIndex(
                earlierItemCollision,
                id: { $0.id },
                items: { $0.items },
                input: input
            )
        }

        let crossSectionCollision = [Section(id: 0, items: [1, 2]), Section(id: 1, items: [2])]
        #expect(throws: DiffInputError.duplicateItemId(
            "2", input: input, first: .init(section: 0, item: 1), duplicate: .init(
                section: 1,
                item: 0
            )
        )) {
            _ = try DiffIndex(
                crossSectionCollision,
                id: { $0.id },
                items: { $0.items },
                input: input
            )
        }
    }

    @Test("Item and section rotations retain the greedy move policy", arguments: [
        ([1, 2, 3, 0], 3),
        ([3, 0, 1, 2], 1)
    ])
    func directionalRotations(target: [Int], expectedMoves: Int) throws {
        let items = try verify(
            from: [Section(id: 0, items: [0, 1, 2, 3])],
            to: [Section(id: 0, items: target)]
        )
        #expect(items.count == 1)
        #expect(items[0].movedItems.count == expectedMoves)
        #expect(items[0].movedSections.isEmpty)

        let sections = try verify(
            from: (0..<4).map { Section(id: $0, items: [$0]) },
            to: target.map { Section(id: $0, items: [$0]) }
        )
        #expect(sections.count == 1)
        #expect(sections[0].movedSections.count == expectedMoves)
        #expect(sections[0].movedItems.isEmpty)
    }

    @Test("All ordered subsets of four items replay correctly")
    func exhaustiveFlatTransitions() throws {
        let sequences = orderedSubsets([0, 1, 2, 3])
        #expect(sequences.count == 65)
        for oldItems in sequences {
            for newItems in sequences {
                try verify(
                    from: [Section(id: 0, items: oldItems)],
                    to: [Section(id: 0, items: newItems)]
                )
            }
        }
    }

    @Test("All structures of two sections and three globally unique items replay correctly")
    func exhaustiveSectionTransitions() throws {
        var structures: [[Section]] = [[]]
        for sectionIds in orderedSubsets([0, 1]) where !sectionIds.isEmpty {
            for items in orderedSubsets([0, 1, 2]) {
                if sectionIds.count == 1 {
                    structures.append([Section(id: sectionIds[0], items: items)])
                } else {
                    for split in 0...items.count {
                        structures.append([
                            Section(id: sectionIds[0], items: Array(items[..<split])),
                            Section(id: sectionIds[1], items: Array(items[split...]))
                        ])
                    }
                }
            }
        }
        #expect(structures.count == 131)
        for source in structures {
            for target in structures { try verify(from: source, to: target) }
        }
    }

    @Test("Two thousand deterministic mixed transitions replay every intermediate stage")
    func randomizedTransitions() throws {
        var generator = Generator(state: 0x506172616465)
        for _ in 0..<2_000 {
            let source = randomStructure(using: &generator)
            let target = randomStructure(using: &generator)
            try verify(from: source, to: target)
        }
    }

    @Test("The same planner replays an independently implemented algorithm")
    func alternativeAlgorithmTransitions() throws {
        var generator = Generator(state: 0x616C7465726E6174)
        for _ in 0..<2_000 {
            let source = randomStructure(using: &generator)
            let target = randomStructure(using: &generator)
            let stages = try plan(from: source, to: target, algorithm: StandardLibraryDiff())
            var current = source
            for stage in stages { current = try replay(stage, from: current) }
            try #require(current == target)
        }
    }

    @Test("Replay derives moved data from the source, not the declared target")
    func replayDoesNotTrustStoredTarget() throws {
        let source = [Section(id: 0, items: [0, 1])]
        let declaredTarget = [Section(id: 0, items: [1, 0])]
        let invalidPlan = Stage(
            sections: declaredTarget,
            movedItems: [(
                from: ItemLocation(section: 0, item: 0),
                to: ItemLocation(section: 0, item: 0)
            )]
        )
        #expect(try replay(invalidPlan, from: source) != declaredTarget)
    }

    private func plan<S: Hashable, I: Hashable>(
        from source: [SectionStructure<S, I>],
        to target: [SectionStructure<S, I>],
        algorithm: any SectionedDiffAlgorithm = SectionedDiff()
    ) throws -> [StructureStage<S, I>] {
        let changes = try algorithm.diff(
            from: source.map { StructuralSection(
                id: $0.id,
                items: $0.items.map { StructuralItem(id: $0) }
            ) },
            to: target.map { StructuralSection(
                id: $0.id,
                items: $0.items.map { StructuralItem(id: $0) }
            ) }
        )
        return try StructurePlanner.stages(for: changes, from: source, to: target)
    }

    @discardableResult
    private func verify(from source: [Section], to target: [Section]) throws -> [Stage] {
        let stages = try plan(from: source, to: target)
        try Stage.validate(stages, from: source, to: target)
        var current = source
        for stage in stages {
            let replayed = try replay(stage, from: current)
            try #require(
                replayed == stage.sections,
                "Invalid intermediate plan from \(source) to \(target)"
            )
            current = replayed
        }
        try #require(current == target, "Plan did not reach target from \(source) to \(target)")
        #expect(stages.count <= 3)
        return stages
    }

    @Test(
        "Plan preflight rejects invalid coordinates, conflicting operations and incorrect identities"
    )
    func malformedPlans() {
        let source = [Section(id: 0, items: [0, 1])]
        let target = [Section(id: 0, items: [1, 0])]
        let invalid = [
            Stage(
                sections: target,
                movedItems: [(.init(section: 0, item: 0), .init(section: 0, item: 0))]
            ),
            Stage(sections: target, deletedItems: [.init(section: 0, item: -1)]),
            Stage(sections: target, insertedItems: [.init(section: 8, item: 0)]),
            Stage(sections: target, movedItems: [
                (.init(section: 0, item: 0), .init(section: 0, item: 0)),
                (.init(section: 0, item: 0), .init(section: 0, item: 1))
            ]),
            Stage(sections: source, movedSections: [(-1, 0)]),
            Stage(
                sections: source,
                movedSections: [(0, 0)],
                deletedItems: [.init(section: 0, item: 0)]
            ),
            Stage(sections: source, insertedSections: IndexSet(integer: 99))
        ]
        for stage in invalid {
            #expect(throws: StructurePlanError.self) {
                try Stage.validate([stage], from: source, to: target)
            }
        }
    }

    @Test("External results reject malformed moves and updates before stage construction")
    func malformedResults() {
        let source = [Section(id: 0, items: [0, 1])]
        let target = [Section(id: 0, items: [1, 0])]
        let move = (from: ItemLocation(section: 0, item: 1), to: ItemLocation(section: 0, item: 0))
        let invalid = [
            SectionedChanges(),
            SectionedChanges(movedItems: [(
                .init(section: 0, item: 0),
                .init(section: 0, item: 0)
            )]),
            SectionedChanges(movedItems: [move, move]),
            SectionedChanges(movedItems: [(
                .init(section: -1, item: 0),
                .init(section: 0, item: 0)
            )]),
            SectionedChanges(updatedSections: [8], movedItems: [move]),
            SectionedChanges(movedItems: [move], updatedItems: [.init(section: 0, item: -1)]),
            SectionedChanges(
                movedItems: [move],
                updatedItems: [.init(section: 0, item: 0), .init(section: 0, item: 0)]
            )
        ]
        for changes in invalid {
            #expect(throws: StructurePlanError.self) {
                try StructurePlanner.stages(for: changes, from: source, to: target)
            }
        }
        let inserted = [Section(id: 1, items: [2])]
        let newContentUpdate = SectionedChanges(
            insertedSections: [0], updatedSections: [0], insertedItems: [.init(section: 0, item: 0)]
        )
        #expect(throws: StructurePlanError.self) {
            try StructurePlanner.stages(for: newContentUpdate, from: [], to: inserted)
        }
        let newItemUpdate = SectionedChanges(
            insertedSections: [0], insertedItems: [.init(section: 0, item: 0)],
            updatedItems: [.init(
                section: 0,
                item: 0
            )]
        )
        #expect(throws: StructurePlanError.self) {
            try StructurePlanner.stages(for: newItemUpdate, from: [], to: inserted)
        }
    }

    @Test("Missing moves cannot be hidden by section insertion or deletion")
    func incompleteTransfers() {
        let source = [Section(id: 0, items: [1])]
        let target = [Section(id: 2, items: [1])]
        let incomplete = SectionedChanges(deletedSections: [0], insertedSections: [0])
        #expect(throws: StructurePlanError.self) {
            try StructurePlanner.stages(for: incomplete, from: source, to: target)
        }
        let sections = [Section(id: 0, items: []), Section(id: 1, items: [])]
        #expect(throws: StructurePlanError.self) {
            try StructurePlanner.stages(
                for: SectionedChanges(),
                from: sections,
                to: sections.reversed()
            )
        }
    }

    @Test("Plan preflight supports optional identities without treating nil as an empty slot")
    func optionalIdentities() throws {
        typealias OptionalSection = SectionStructure<Int?, Int?>
        let source = [OptionalSection(id: nil, items: [nil, 1])]
        let target = [OptionalSection(id: nil, items: [1, nil])]
        let stages = try plan(from: source, to: target)
        try StructureStage.validate(stages, from: source, to: target)
        #expect(stages.count == 1)
    }

    /// Replay simultaneous removals and destinations independently. Only inserted
    /// values are read from stage.sections; surviving/moved values come from source.
    private func replay(_ stage: Stage, from source: [Section]) throws -> [Section] {
        try check(!stage.isEmpty, "Empty stage")
        let hasSectionEdits = !stage.deletedSections.isEmpty || !stage.insertedSections.isEmpty ||
            !stage.movedSections.isEmpty
        if hasSectionEdits {
            try check(
                stage.deletedItems.isEmpty && stage.insertedItems.isEmpty &&
                    stage.movedItems.isEmpty,
                "Mixed section and item edits"
            )
            let count = source.count - stage.deletedSections.count + stage.insertedSections.count
            try check(count >= 0 && stage.sections.count == count, "Invalid section count")
            var result = [Section?](repeating: nil, count: count)
            var removed = Set<Int>()
            for index in stage.deletedSections {
                try check(source.indices.contains(index), "Invalid section deletion")
                try check(removed.insert(index).inserted, "Duplicate section source")
            }
            for index in stage.insertedSections {
                try check(result.indices.contains(index), "Invalid section insertion")
                result[index] = stage.sections[index]
            }
            for move in stage.movedSections {
                try check(
                    source.indices.contains(move.from) && result.indices.contains(move.to),
                    "Invalid section move"
                )
                try check(
                    removed.insert(move.from).inserted && result[move.to] == nil,
                    "Conflicting section move"
                )
                result[move.to] = source[move.from]
            }
            var retained = source.indices.filter { !removed.contains($0) }.makeIterator()
            for index in result.indices where result[index] == nil {
                guard let origin = retained.next() else {
                    throw ReplayError("Missing retained section")
                }
                result[index] = source[origin]
            }
            try check(retained.next() == nil, "Extra retained section")
            return result.compactMap { $0 }
        }

        try check(source.map(\.id) == stage.sections.map(\.id), "Item stage changed sections")
        var removed = Set<ItemLocation>()
        var slots = stage.sections.map { [Int?](repeating: nil, count: $0.items.count) }
        var additions = [Int](repeating: 0, count: source.count)
        var removals = [Int](repeating: 0, count: source.count)
        for origin in stage.deletedItems {
            try check(contains(origin, in: source), "Invalid item deletion")
            try check(removed.insert(origin).inserted, "Duplicate item source")
            removals[origin.section] += 1
        }
        for destination in stage.insertedItems {
            try check(contains(destination, in: stage.sections), "Invalid item insertion")
            try check(
                slots[destination.section][destination.item] == nil,
                "Duplicate item destination"
            )
            slots[destination.section][destination.item] =
                stage.sections[destination.section].items[destination.item]
            additions[destination.section] += 1
        }
        for move in stage.movedItems {
            try check(
                contains(move.from, in: source) && contains(move.to, in: stage.sections),
                "Invalid item move"
            )
            try check(
                removed.insert(move.from).inserted && slots[move.to.section][move.to.item] == nil,
                "Conflicting item move"
            )
            slots[move.to.section][move.to.item] = source[move.from.section].items[move.from.item]
            removals[move.from.section] += 1
            additions[move.to.section] += 1
        }
        for section in source.indices {
            let count = source[section].items.count - removals[section] + additions[section]
            try check(slots[section].count == count, "Invalid item count")
            var retained = source[section].items.indices.filter {
                !removed.contains(ItemLocation(section: section, item: $0))
            }.makeIterator()
            for item in slots[section].indices where slots[section][item] == nil {
                guard let origin = retained.next() else {
                    throw ReplayError("Missing retained item")
                }
                slots[section][item] = source[section].items[origin]
            }
            try check(retained.next() == nil, "Extra retained item")
        }
        return source.indices.map { Section(id: source[$0].id, items: slots[$0].compactMap { $0 }) }
    }

    private func contains(_ location: ItemLocation, in sections: [Section]) -> Bool {
        sections.indices.contains(location.section) &&
            sections[location.section].items.indices.contains(location.item)
    }

    private func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw ReplayError(message) }
    }

    private struct ReplayError: Error, CustomStringConvertible {
        var description: String
        init(_ description: String) { self.description = description }
    }

    private func orderedSubsets(_ values: [Int]) -> [[Int]] {
        var output: [[Int]] = [[]]
        for (index, value) in values.enumerated() {
            var remaining = values
            remaining.remove(at: index)
            output += orderedSubsets(remaining).map { [value] + $0 }
        }
        return output
    }

    private struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    private func randomStructure(using generator: inout Generator) -> [Section] {
        let count = Int.random(in: 0...6, using: &generator)
        var sections = Array(0..<6).shuffled(using: &generator).prefix(count).map {
            Section(id: $0, items: [])
        }
        guard !sections.isEmpty else { return [] }
        let items = Array(0..<24).shuffled(using: &generator).prefix(Int.random(
            in: 0...24,
            using: &generator
        ))
        for item in items {
            sections[Int.random(in: sections.indices, using: &generator)].items.append(item)
        }
        return sections
    }
}

private struct StructuralItem<Id: Hashable>: DiffableElement {
    let id: Id
}

private struct StructuralSection<Id: Hashable, ItemId: Hashable>: DiffableSection {
    let id: Id
    let items: [StructuralItem<ItemId>]
    func isContentEqual(to other: Self) -> Bool { true }
}
