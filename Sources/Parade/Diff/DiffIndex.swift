// Created by weixi on 2026/09/17.

struct DiffIndex<SectionId: Hashable, ItemId: Hashable> {
    let sectionIndices: [SectionId: Int]
    let itemLocations: [ItemId: ItemLocation]

    init<Section>(
        _ sections: [Section],
        id: (Section) -> SectionId,
        items: (Section) -> [ItemId],
        input: DiffInputError.Input
    ) throws {
        var sectionIndices = IndexBuilder<SectionId, Int>(minimumCapacity: sections.count)
        var itemLocations = IndexBuilder<ItemId, ItemLocation>(
            minimumCapacity: sections.count
        )
        for (sectionIndex, section) in sections.enumerated() {
            try sectionIndices.insert(sectionIndex, forKey: id(section)) { id, first, duplicate in
                DiffInputError.duplicateSectionId(
                    String(describing: id),
                    input: input,
                    first: first,
                    duplicate: duplicate
                )
            }
            for (itemIndex, id) in items(section).enumerated() {
                let location = ItemLocation(section: sectionIndex, item: itemIndex)
                try itemLocations.insert(location, forKey: id) { id, first, duplicate in
                    DiffInputError.duplicateItemId(
                        String(describing: id),
                        input: input,
                        first: first,
                        duplicate: duplicate
                    )
                }
            }
        }
        self.sectionIndices = sectionIndices.values
        self.itemLocations = itemLocations.values
    }
}
