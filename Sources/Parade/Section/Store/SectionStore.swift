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
public final class SectionStore<Layout>: SectionControllerQuery {
    /// Instance membership for one reconciliation, not an immutable display snapshot.
    /// Keeping a change alive also retains its controllers, including removed instances.
    @MainActor
    public struct Change: SectionControllerQuery {
        /// The complete target order, including new and retained instances.
        public var controllers: [any SectionController<Layout>] {
            instances.map { $0.controller }
        }

        /// Instances reused from the previous membership, in target order.
        /// Fresh definitions have applied their inputs; retaining definitions leave state untouched.
        /// Their presentations have not been submitted.
        public let retained: [any SectionController<Layout>]

        /// Reused instances whose input update closure ran in this reconciliation, in target order.
        /// A subset of `retained`: excludes creation, replacement, and retaining definitions.
        /// Repeated equal input counts. This is neither a content diff nor a delivery receipt,
        /// and does not accumulate pending updates across failed submissions or retries.
        public let inputUpdated: [any SectionController<Layout>]

        /// Instances absent from the target, in previous order. Includes same-ID replacements.
        public let removed: [any SectionController<Layout>]

        /// Whether instance membership or order changed. Content changes alone do not set this.
        public let hasStructuralChanges: Bool

        /// Searches this change's target membership, including before the store accepts it.
        /// Membership is fixed, but the returned instance's state can continue changing.
        public func controller<Controller: SectionController<Layout>>(
            for id: Controller.Id, as type: Controller.Type
        ) -> Controller? {
            instances.first { $0.id == AnyHashable(id) }?.controller as? Controller
        }

        public func controllers<Controller: SectionController<Layout>>(
            ofType type: Controller.Type
        ) -> [Controller] {
            instances.compactMap { $0.controller as? Controller }
        }

        fileprivate let instances: [any StoredSection<Layout>]
    }

    public init() {}

    public var ids: [AnyHashable] {
        orderedInstances.map(\.id)
    }

    public var controllers: [any SectionController<Layout>] {
        orderedInstances.map { $0.controller }
    }

    /// Looks up accepted membership through the store's ID index.
    /// During async reconciliation, membership remains old until apply succeeds,
    /// but surviving instances may already contain the new input.
    public func controller<Controller: SectionController<Layout>>(
        for id: Controller.Id, as type: Controller.Type
    ) -> Controller? {
        instancesById[AnyHashable(id)]?.controller as? Controller
    }

    public func controllers<Controller: SectionController<Layout>>(
        ofType type: Controller.Type
    ) -> [Controller] {
        orderedInstances.compactMap { $0.controller as? Controller }
    }

    /// Fresh, short-lived definitions for reordering/removing current instances without
    /// applying inputs. Do not cache them: they retain the instances at the time of access.
    /// Typed definitions supplied in a later reconciliation still update those same instances.
    public var retainingDefinitions: [SectionDefinition<Layout>] {
        orderedInstances.map { SectionDefinition(retaining: $0) }
    }

    /// Accepts the resolved instances and order immediately, without submitting presentations.
    /// Duplicate IDs reject the entire input before any factory or update closure runs.
    /// Use the async overload when accepting membership must await an external submission.
    @discardableResult
    public func reconcile(_ definitions: [SectionDefinition<Layout>]) throws(CollectionUpdateError) -> Change {
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
        _ definitions: [SectionDefinition<Layout>],
        apply: @MainActor (Change) async throws -> Void
    ) async throws -> Change {
        let change = try resolve(definitions)
        try await apply(change)
        accept(change)
        return change
    }

    private func resolve(_ definitions: [SectionDefinition<Layout>]) throws(CollectionUpdateError) -> Change {
        var uniqueIds = Set<AnyHashable>()
        for definition in definitions {
            guard uniqueIds.insert(definition.id).inserted else {
                throw .duplicateSectionId(String(describing: definition.id))
            }
        }

        let resolved = definitions.map { $0.resolve(instancesById[$0.id]) }
        let next = resolved.map(\.instance)
        let previousIdentities = orderedInstances.map { ObjectIdentifier($0.controller) }
        let nextIdentities = next.map { ObjectIdentifier($0.controller) }
        let previous = Set(previousIdentities)
        let incoming = Set(nextIdentities)
        return Change(
            retained: next.filter { previous.contains(ObjectIdentifier($0.controller)) }.map { $0.controller },
            inputUpdated: resolved.filter {
                $0.didUpdateInput && previous.contains(ObjectIdentifier($0.instance.controller))
            }.map { $0.instance.controller },
            removed: orderedInstances.filter { !incoming.contains(ObjectIdentifier($0.controller)) }.map { $0.controller },
            hasStructuralChanges: previousIdentities != nextIdentities,
            instances: next
        )
    }

    private func accept(_ change: Change) {
        orderedInstances = change.instances
        instancesById = Dictionary(uniqueKeysWithValues: change.instances.map { ($0.id, $0) })
    }

    private var orderedInstances: [any StoredSection<Layout>] = []
    private var instancesById: [AnyHashable: any StoredSection<Layout>] = [:]
}
