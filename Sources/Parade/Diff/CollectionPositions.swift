// Created by weixi on 2026/09/17.

/// Identity-to-position lookups used during difference calculation and validation.
/// Construction rejects the first duplicate in section/item traversal order.
struct CollectionPositions<SectionId: Hashable, ItemId: Hashable> {
    let sectionIndices: [SectionId: Int]
    let itemLocations: [ItemId: ItemLocation]

    init<Section: DiffableSection>(
        _ sections: [Section],
        input: DiffInputError.Input
    ) throws where Section.Id == SectionId, Section.Item.Id == ItemId {
        var sectionIndices = [SectionId: Int](minimumCapacity: sections.count)
        var itemLocations: [ItemId: ItemLocation] = [:]
        for (sectionIndex, section) in sections.enumerated() {
            if let first = sectionIndices.updateValue(sectionIndex, forKey: section.id) {
                throw DiffInputError.duplicateSectionId(
                    String(describing: section.id), input: input,
                    first: first, duplicate: sectionIndex
                )
            }
            for (itemIndex, item) in section.items.enumerated() {
                let location = ItemLocation(section: sectionIndex, item: itemIndex)
                if let first = itemLocations.updateValue(location, forKey: item.id) {
                    throw DiffInputError.duplicateItemId(
                        String(describing: item.id), input: input,
                        first: first, duplicate: location
                    )
                }
            }
        }
        self.sectionIndices = sectionIndices
        self.itemLocations = itemLocations
    }
}
