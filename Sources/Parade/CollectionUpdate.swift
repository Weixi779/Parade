//
//  Created by weixi on 2026/9/17.
//

/// A description of one collection update. Building or copying it has no side effects.
/// Each apply captures current section content before entering the collection's queue.
/// The description retains its collection and sections; it is not a display snapshot.
@MainActor
public struct CollectionUpdate {
    private let owner: CollectionOrchestrator
    private let composition: [any SectionController]?
    private var updatedSections: [any SectionController] = []

    init(owner: CollectionOrchestrator, composition: [any SectionController]? = nil) {
        self.owner = owner
        self.composition = composition
    }

    /// Includes these sections' current content in the update. Repeated calls accumulate;
    /// each instance is captured once. In a composition, selections must belong to its target.
    public func updating(_ sections: [any SectionController]) -> Self {
        var update = self
        var identities = Set(updatedSections.map { ObjectIdentifier($0) })
        update.updatedSections += sections.filter { identities.insert(ObjectIdentifier($0)).inserted }
        return update
    }

    /// Captures now, submits one combined target, and awaits content, layout and binding updates.
    /// Reapplying a description makes a new submission with a fresh content capture.
    public func apply(animated: Bool = true, mode: CollectionUpdateMode = .diff) async throws {
        try await withCheckedThrowingContinuation { continuation in
            apply(animated: animated, mode: mode) { continuation.resume(with: $0) }
        }
    }

    /// The callback form has the same capture and completion boundary as async apply.
    public func apply(
        animated: Bool = true,
        mode: CollectionUpdateMode = .diff,
        completion: @escaping @MainActor (Result<Void, CollectionUpdateError>) -> Void
    ) {
        owner.apply(composition: composition, updating: updatedSections, animated: animated, mode: mode, completion: completion)
    }
}

/// How a submitted snapshot replaces the last applied snapshot.
public enum CollectionUpdateMode: Sendable {
    case diff
    case reload
}

/// Invalid identity or supplementary placement is rejected before UIKit is mutated.
public enum CollectionUpdateError: Error, Equatable, Sendable {
    case updateChannelClosed
    case sectionNotAttached
    case sectionAlreadyAttached
    case staleSectionInstance(String)
    case sectionNotInComposition(String)
    case duplicateSectionId(String)
    case duplicateCellId(String)
    case duplicateSupplementaryId(section: String, kind: String, id: String)
    case duplicateSupplementaryPlacement(section: String, kind: String, item: Int)
    case invalidSupplementaryPlacement(section: String, kind: String, item: Int)
}
