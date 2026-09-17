// Created by weixi on 2026/09/17.

import Foundation

/// The identity-only structure of one captured section.
struct SectionStructure<SectionId: Hashable, ItemId: Hashable>: Equatable {
    var id: SectionId
    var items: [ItemId]
}

extension SectionStructure: Sendable where SectionId: Sendable, ItemId: Sendable {}

/// All removals and move sources use the previous stage's coordinates. All
/// insertions and move destinations use this stage's resulting coordinates.
struct StructureStage<SectionId: Hashable, ItemId: Hashable> {
    var sections: [SectionStructure<SectionId, ItemId>]
    var deletedSections = IndexSet()
    var insertedSections = IndexSet()
    var movedSections: [(from: Int, to: Int)] = []
    var deletedItems: [ItemLocation] = []
    var insertedItems: [ItemLocation] = []
    var movedItems: [(from: ItemLocation, to: ItemLocation)] = []

    var isEmpty: Bool {
        deletedSections.isEmpty && insertedSections.isEmpty && movedSections.isEmpty
            && deletedItems.isEmpty && insertedItems.isEmpty && movedItems.isEmpty
    }
}

extension StructureStage: Sendable where SectionId: Sendable, ItemId: Sendable {}
