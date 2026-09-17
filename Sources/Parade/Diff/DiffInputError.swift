// Created by weixi on 2026/09/17.

public enum DiffInputError: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Input: String, Sendable {
        case source
        case target
    }

    case duplicateSectionId(String, input: Input, first: Int, duplicate: Int)
    case duplicateItemId(String, input: Input, first: ItemLocation, duplicate: ItemLocation)

    public var description: String {
        switch self {
        case let .duplicateSectionId(id, input, first, duplicate):
            "Duplicate section Id '\(id)' in \(input.rawValue) at sections \(first) and \(duplicate)."
        case let .duplicateItemId(id, input, first, duplicate):
            "Duplicate cell Id '\(id)' in \(input.rawValue) at "
                + "[\(first.section), \(first.item)] and [\(duplicate.section), \(duplicate.item)]. "
                + "Cell IDs must be unique across the collection."
        }
    }
}
