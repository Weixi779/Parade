// Created by weixi on 2026/09/17.

import Foundation

/// One UIKit batch and the contents its data source must expose during that batch.
/// Removal/move origins use the previous contents; destinations use `sections`.
struct CollectionBatch {
    var sections: [SectionSnapshot]
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
