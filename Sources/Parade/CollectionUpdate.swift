//
//  Created by weixi on 2026/9/17.
//

/// How a submitted composition replaces the last applied composition.
public enum CollectionUpdateMode: Sendable {
    case diff
    case reload
}

/// Invalid identity or supplementary placement is rejected before UIKit is mutated.
public enum CollectionUpdateError: Error, Equatable, Sendable {
    case duplicateSectionId(String)
    case duplicateCellId(String)
    case duplicateSupplementaryId(section: String, kind: String, id: String)
    case duplicateSupplementaryPlacement(section: String, kind: String, item: Int)
    case invalidSupplementaryPlacement(section: String, kind: String, item: Int)
}
