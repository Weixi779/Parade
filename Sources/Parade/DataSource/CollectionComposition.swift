// Created by weixi on 2026/09/17.

import Foundation

/// A captured, validated input. Only these compositions may become an applied
/// baseline or a reload target; intermediate contents belong to update batches.
public struct CollectionComposition {
    public let sections: [SectionContent]
    public let sectionsById: [AnyHashable: SectionContent]
    public let cellsById: [AnyHashable: AnyCellPresenter]

    public static var empty: Self { Self() }

    private init() {
        sections = []
        sectionsById = [:]
        cellsById = [:]
    }

    /// Validate each section completely before the next, preserving error order.
    init(_ sections: [SectionContent]) throws(ValidationFailure) {
        var sectionLocations = [AnyHashable: Int](minimumCapacity: sections.count)
        var cellLocations: [AnyHashable: ItemLocation] = [:]
        for (sectionIndex, section) in sections.enumerated() {
            if let first = sectionLocations.updateValue(sectionIndex, forKey: section.id) {
                throw ValidationFailure(
                    .duplicateSectionId(String(describing: section.id)),
                    locations: [.init(section: first), .init(section: sectionIndex)]
                )
            }
            for (item, presenter) in section.cells.enumerated() {
                let location = ItemLocation(section: sectionIndex, item: item)
                if let first = cellLocations.updateValue(location, forKey: presenter.id) {
                    throw ValidationFailure(
                        .duplicateCellId(String(describing: presenter.id)),
                        locations: [
                            .init(section: first.section, item: first.item),
                            .init(section: sectionIndex, item: item)
                        ]
                    )
                }
            }
            try Self.validateSupplementaries(in: section, at: sectionIndex)
        }
        self.sections = sections
        sectionsById = sectionLocations.mapValues { sections[$0] }
        cellsById = cellLocations.mapValues { sections[$0.section].cells[$0.item] }
    }

    struct ValidationFailure: Error {
        let error: CollectionUpdateError
        let diagnostic: CollectionDiagnostic

        init(_ error: CollectionUpdateError, locations: [CollectionDiagnostic.Location]) {
            self.error = error
            diagnostic = CollectionDiagnostic(
                reason: .invalidUpdate(error), recovery: .rejectedUpdate, locations: locations
            )
        }
    }
}

private extension CollectionComposition {
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
        var placements: [SupplementaryAddress: CollectionDiagnostic.Location] = [:]
        var identities: [SupplementaryIdentity: CollectionDiagnostic.Location] = [:]
        for presenter in section.supplementaryViews {
            let address = SupplementaryAddress(kind: presenter.elementKind, item: presenter.itemIndex)
            let location = CollectionDiagnostic.Location(section: sectionIndex, item: address.item)
            guard !address.kind.isEmpty, address.item >= 0 else {
                throw ValidationFailure(
                    .invalidSupplementaryPlacement(
                        section: sectionDescription, kind: address.kind, item: address.item
                    ),
                    locations: [location]
                )
            }
            if let first = placements.updateValue(location, forKey: address) {
                throw ValidationFailure(
                    .duplicateSupplementaryPlacement(
                        section: sectionDescription, kind: address.kind, item: address.item
                    ),
                    locations: [first, location]
                )
            }
            let identity = SupplementaryIdentity(kind: address.kind, id: presenter.id)
            if let first = identities.updateValue(location, forKey: identity) {
                throw ValidationFailure(
                    .duplicateSupplementaryId(
                        section: sectionDescription, kind: identity.kind,
                        id: String(describing: identity.id)
                    ),
                    locations: [first, location]
                )
            }
        }
    }
}
