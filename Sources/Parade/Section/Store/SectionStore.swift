// Created by weixi on 2026/09/23.

import Foundation

/// Maintains an ordered set of stable section instances from changing definitions.
///
/// Retain one store for the composition it owns. The store creates, updates, reorders,
/// and releases its instances; it does not capture presentations, attach sections,
/// or submit UIKit updates. Applications may also manage controllers directly without a store.
///
/// Serialize reconciliations, including across suspension in `reconcile(_:apply:)`.
/// Neither definition closures nor the apply callback may reenter this store.
@MainActor
public final class SectionStore {
    /// Instance membership for one reconciliation, not an immutable display snapshot.
    /// Keeping a change alive also retains its controllers, including removed instances.
    @MainActor
    public struct Change {
        /// The complete target order, including new and retained instances.
        public var controllers: [any SectionController] {
            instances.map(\.controller)
        }

        /// Instances reused from the previous membership, in target order.
        /// Their business inputs have been updated; their presentations have not been submitted.
        public let retained: [any SectionController]

        /// Instances absent from the target, in previous order. Includes same-ID replacements.
        public let removed: [any SectionController]

        /// Whether instance membership or order changed. Content changes alone do not set this.
        public let hasStructuralChanges: Bool

        fileprivate let instances: [any StoredSection]
    }

    public init() {}

    public var ids: [AnyHashable] {
        orderedInstances.map(\.id)
    }

    public var controllers: [any SectionController] {
        orderedInstances.map(\.controller)
    }

    /// Accepts the resolved instances and order immediately, without submitting presentations.
    /// Duplicate IDs reject the entire input before any factory or update closure runs.
    /// Use the async overload when accepting membership must await an external submission.
    @discardableResult
    public func reconcile(_ definitions: [SectionDefinition]) throws(CollectionUpdateError) -> Change {
        let change = try resolve(definitions)
        accept(change)
        return change
    }

    /// Awaits one application-defined submission before accepting instances and order.
    ///
    /// `apply` runs for every valid reconciliation, including content-only changes.
    /// Use it to compose the target controllers and select which retained content to update.
    /// After it succeeds, the store accepts that membership and returns the change.
    ///
    /// On error (including cancellation thrown by `apply`), membership and order remain
    /// unchanged. Retained controllers have already received their inputs: their business
    /// state and callback side effects are not rolled back.
    @discardableResult
    public func reconcile(
        _ definitions: [SectionDefinition],
        apply: @MainActor (Change) async throws -> Void
    ) async throws -> Change {
        let change = try resolve(definitions)
        try await apply(change)
        accept(change)
        return change
    }

    private func resolve(_ definitions: [SectionDefinition]) throws(CollectionUpdateError) -> Change {
        var uniqueIds = Set<AnyHashable>()
        for definition in definitions {
            guard uniqueIds.insert(definition.id).inserted else {
                throw .duplicateSectionId(String(describing: definition.id))
            }
        }

        let next = definitions.map { $0.resolve(instancesById[$0.id]) }
        let previousIdentities = orderedInstances.map { ObjectIdentifier($0.controller) }
        let nextIdentities = next.map { ObjectIdentifier($0.controller) }
        let previous = Set(previousIdentities)
        let incoming = Set(nextIdentities)
        return Change(
            retained: next.filter { previous.contains(ObjectIdentifier($0.controller)) }.map(\.controller),
            removed: orderedInstances.filter { !incoming.contains(ObjectIdentifier($0.controller)) }.map(\.controller),
            hasStructuralChanges: previousIdentities != nextIdentities,
            instances: next
        )
    }

    private func accept(_ change: Change) {
        orderedInstances = change.instances
        instancesById = Dictionary(uniqueKeysWithValues: change.instances.map { ($0.id, $0) })
    }

    private var orderedInstances: [any StoredSection] = []
    private var instancesById: [AnyHashable: any StoredSection] = [:]
}
