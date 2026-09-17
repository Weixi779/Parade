// Created by weixi on 2026/09/17.

/// Validates captured input while building its presenter lookups. Each section
/// is checked completely before the next, preserving the first reported error.
struct CollectionInputIndex {
    let sectionsById: [AnyHashable: SectionContent]
    let cellsById: [AnyHashable: AnyCellPresenter]

    init(_ sections: [SectionContent]) throws(ValidationFailure) {
        var sectionIndex = IndexBuilder<AnyHashable, Occurrence<SectionContent>>(
            minimumCapacity: sections.count
        )
        var cellIndex = IndexBuilder<AnyHashable, Occurrence<AnyCellPresenter>>()

        for (sectionOffset, section) in sections.enumerated() {
            try sectionIndex.insert(
                Occurrence(value: section, location: Location(section: sectionOffset)),
                forKey: section.id
            ) { id, first, duplicate in
                ValidationFailure(
                    .duplicateSectionId(String(describing: id)),
                    locations: [first.location, duplicate.location]
                )
            }

            for (itemOffset, presenter) in section.cells.enumerated() {
                try cellIndex.insert(
                    Occurrence(
                        value: presenter,
                        location: Location(section: sectionOffset, item: itemOffset)
                    ),
                    forKey: presenter.id
                ) { id, first, duplicate in
                    ValidationFailure(
                        .duplicateCellId(String(describing: id)),
                        locations: [first.location, duplicate.location]
                    )
                }
            }

            try Self.validateSupplementaries(in: section, at: sectionOffset)
        }

        sectionsById = sectionIndex.values.mapValues(\.value)
        cellsById = cellIndex.values.mapValues(\.value)
    }

    struct ValidationFailure: Error {
        let error: CollectionUpdateError
        let diagnostic: CollectionDiagnostic

        init(
            _ error: CollectionUpdateError,
            locations: [CollectionDiagnostic.Location]
        ) {
            self.error = error
            diagnostic = CollectionDiagnostic(
                reason: .invalidUpdate(error),
                recovery: .rejectedUpdate,
                locations: locations
            )
        }
    }
}

private extension CollectionInputIndex {
    typealias Location = CollectionDiagnostic.Location

    struct Occurrence<Value> {
        let value: Value
        let location: Location
    }

    struct SupplementaryAddress: Hashable {
        let kind: String
        let item: Int
    }

    struct SupplementaryIdentity: Hashable {
        let kind: String
        let id: AnyHashable
    }

    static func validateSupplementaries(
        in section: SectionContent,
        at sectionIndex: Int
    ) throws(ValidationFailure) {
        let sectionDescription = String(describing: section.id)
        var placements = IndexBuilder<SupplementaryAddress, Location>()
        var identities = IndexBuilder<SupplementaryIdentity, Location>()

        for presenter in section.supplementaryViews {
            let address = SupplementaryAddress(
                kind: presenter.elementKind,
                item: presenter.itemIndex
            )
            let location = Location(section: sectionIndex, item: address.item)

            guard !address.kind.isEmpty, address.item >= 0 else {
                throw ValidationFailure(
                    .invalidSupplementaryPlacement(
                        section: sectionDescription,
                        kind: address.kind,
                        item: address.item
                    ),
                    locations: [location]
                )
            }

            try placements.insert(location, forKey: address) { address, first, duplicate in
                ValidationFailure(
                    .duplicateSupplementaryPlacement(
                        section: sectionDescription,
                        kind: address.kind,
                        item: address.item
                    ),
                    locations: [first, duplicate]
                )
            }

            let identity = SupplementaryIdentity(kind: address.kind, id: presenter.id)
            try identities.insert(location, forKey: identity) { identity, first, duplicate in
                ValidationFailure(
                    .duplicateSupplementaryId(
                        section: sectionDescription,
                        kind: identity.kind,
                        id: String(describing: identity.id)
                    ),
                    locations: [first, duplicate]
                )
            }
        }
    }
}
