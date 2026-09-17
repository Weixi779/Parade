// Created by weixi on 2026/09/17.

import Foundation

public struct ItemLocation: Hashable, Sendable {
    public var section: Int
    public var item: Int

    public init(section: Int, item: Int) {
        self.section = section
        self.item = item
    }
}

/// Logical changes between two section collections, before UI batching.
///
/// Deletions and move sources use source coordinates. Insertions, updates and move
/// destinations use target coordinates. Updates may overlap moves, but only refer
/// to retained identities. Section updates exclude changes to their items.
///
/// Insert/delete lists contain every new/removed identity, including items inside
/// inserted/deleted sections. Retained items crossing sections must be moves.
/// Other retained identities fill unoccupied destinations in source order within
/// their section. A section move carries its items and does not itself move them.
public struct SectionedChanges: Sendable {
    public var deletedSections: IndexSet
    public var insertedSections: IndexSet
    public var movedSections: [(from: Int, to: Int)]
    public var updatedSections: IndexSet
    public var deletedItems: [ItemLocation]
    public var insertedItems: [ItemLocation]
    public var movedItems: [(from: ItemLocation, to: ItemLocation)]
    public var updatedItems: [ItemLocation]

    public init(
        deletedSections: IndexSet = [],
        insertedSections: IndexSet = [],
        movedSections: [(from: Int, to: Int)] = [],
        updatedSections: IndexSet = [],
        deletedItems: [ItemLocation] = [],
        insertedItems: [ItemLocation] = [],
        movedItems: [(from: ItemLocation, to: ItemLocation)] = [],
        updatedItems: [ItemLocation] = []
    ) {
        self.deletedSections = deletedSections
        self.insertedSections = insertedSections
        self.movedSections = movedSections
        self.updatedSections = updatedSections
        self.deletedItems = deletedItems
        self.insertedItems = insertedItems
        self.movedItems = movedItems
        self.updatedItems = updatedItems
    }

    public var isEmpty: Bool {
        deletedSections.isEmpty && insertedSections.isEmpty && movedSections.isEmpty &&
            updatedSections.isEmpty && deletedItems.isEmpty && insertedItems.isEmpty &&
            movedItems.isEmpty && updatedItems.isEmpty
    }
}
