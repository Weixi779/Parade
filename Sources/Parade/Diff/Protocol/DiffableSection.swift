// Created by weixi on 2026/09/17.

/// One captured section. Section IDs are unique within an input; item IDs are
/// unique across all its sections, so an item can retain identity when transferred.
public protocol DiffableSection {
    associatedtype Id: Hashable
    associatedtype Item: DiffableElement

    var id: Id { get }
    var items: [Item] { get }

    /// Compares the section's own content, excluding its items. Called only for
    /// matching IDs. A section with no content of its own can always return true.
    func isContentEqual(to other: Self) -> Bool
}
