// Created by weixi on 2026/09/17.

import Foundation

/// A captured, validated input. Only these compositions may become an applied
/// baseline or a reload target; intermediate stages belong to the changeset.
struct CollectionComposition {
    let sections: [SectionContent]
    let sectionsById: [AnyHashable: SectionContent]
    let cellsById: [AnyHashable: AnyCellPresenter]

    static var empty: Self { Self() }

    private init() {
        sections = []
        sectionsById = [:]
        cellsById = [:]
    }

    var structure: [SectionStructure<AnyHashable, AnyHashable>] {
        sections.map(\.structure)
    }

    init(_ sections: [SectionContent]) throws(ValidationFailure) {
        let index = try CollectionInputIndex(sections)
        self.sections = sections
        sectionsById = index.sectionsById
        cellsById = index.cellsById
    }

    typealias ValidationFailure = CollectionInputIndex.ValidationFailure
}
