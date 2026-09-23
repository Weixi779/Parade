// Created by weixi on 2026/09/23.

import Foundation
import Parade
import Testing

@MainActor
@Suite("Section instance reconciliation", .timeLimit(.minutes(1)))
struct SectionStoreTests {
    @Test("An empty composition needs no structural submission")
    func emptyComposition() async throws {
        let store = SectionStore()
        let change = try await store.reconcile([]) { _ in
            Issue.record("An unchanged empty store must not submit membership")
        }

        #expect(store.ids.isEmpty)
        #expect(store.presenters.isEmpty)
        #expect(change.presenters.isEmpty)
        #expect(change.retained.isEmpty)
        #expect(change.removed.isEmpty)
        #expect(!change.hasStructuralChanges)
    }

    @Test("Definitions are lazy and creation does not also run the updater")
    func lazyCreation() throws {
        var creations = 0
        let definition = SectionDefinition(id: "a", input: "initial", make: {
            creations += 1
            return Presenter<Regular>("a", value: $0)
        }, update: { _, _ in
            Issue.record("A new instance already received its input through make")
        })
        #expect(definition.id == AnyHashable("a"))
        #expect(creations == 0)

        let store = SectionStore()
        let change = try store.reconcile([definition])
        let section = try #require(store.presenters.first as? Presenter<Regular>)
        #expect(creations == 1)
        #expect(section.value == "initial")
        #expect(!section.updates.isAttached)
        #expect(change.hasStructuralChanges)
        #expect(change.retained.isEmpty)
        #expect(change.removed.isEmpty)
        #expect(change.presenters.first === section)
    }

    @Test("Reused instances keep local state and receive the current update closure")
    func retainedState() throws {
        let store = SectionStore()
        try store.reconcile([definition("a", value: "first")])
        let section = try #require(store.presenters.first as? Presenter<Regular>)
        section.isExpanded = true

        let change = try store.reconcile([
            SectionDefinition(id: "a", input: "second", make: {
                Issue.record("Matching instances must not be reconstructed")
                return Presenter<Regular>("a", value: $0)
            }, update: { $0.value = "current closure: \($1)" }),
        ])

        #expect(store.presenters.first === section)
        #expect(change.retained.first === section)
        #expect(section.value == "current closure: second")
        #expect(section.isExpanded)
        #expect(!change.hasStructuralChanges)
    }

    @Test("Repeated input still reaches state that changed locally")
    func repeatedInput() async throws {
        let store = SectionStore()
        try store.reconcile([definition("a", value: "server")])
        let section = try #require(store.presenters.first as? Presenter<Regular>)
        section.value = "local edit"

        let change = try await store.reconcile([definition("a", value: "server")]) { _ in
            Issue.record("Content changes must not resubmit membership")
        }

        #expect(section.value == "server")
        #expect(change.retained.first === section)
        #expect(!change.hasStructuralChanges)
    }

    @Test("The same input type may feed different concrete presenters")
    func heterogeneousPresenters() throws {
        let store = SectionStore()
        try store.reconcile([
            definition("regular", value: "one"),
            SectionDefinition(id: "featured", input: "two", make: {
                Presenter<Featured>("featured", value: $0)
            }, update: { $0.value = $1 }),
        ])
        let regular = try #require(store.presenters.first as? Presenter<Regular>)
        let featured = try #require(store.presenters.last as? Presenter<Featured>)

        let change = try store.reconcile([
            SectionDefinition(id: "featured", input: "updated", make: {
                Presenter<Featured>("featured", value: $0)
            }, update: { $0.value = $1 }),
            definition("regular", value: "also updated"),
        ])

        #expect(store.ids == [AnyHashable("featured"), AnyHashable("regular")])
        #expect(change.retained.count == 2)
        #expect(change.retained.first === featured)
        #expect(change.retained.last === regular)
        #expect(regular.value == "also updated")
        #expect(featured.value == "updated")
    }

    @Test("Changing presenter type replaces the instance under the same ID")
    func presenterTypeReplacement() throws {
        let store = SectionStore()
        try store.reconcile([definition("a")])
        let previous = try #require(store.presenters.first)

        let change = try store.reconcile([
            SectionDefinition(id: "a", input: "replacement", make: {
                Presenter<Featured>("a", value: $0)
            }, update: { _, _ in Issue.record("A replacement must be created, not updated") }),
        ])

        #expect(change.hasStructuralChanges)
        #expect(change.retained.isEmpty)
        #expect(change.removed.count == 1)
        #expect(change.removed.first === previous)
        #expect(store.presenters.first is Presenter<Featured>)
        #expect(store.presenters.first !== previous)
        #expect(store.ids == [AnyHashable("a")])
    }

    @Test("Changing input type replaces the association even with the same presenter type")
    func inputTypeReplacement() throws {
        let store = SectionStore()
        try store.reconcile([definition("a")])
        let previous = try #require(store.presenters.first)

        let change = try store.reconcile([
            SectionDefinition(id: "a", input: 42, make: {
                Presenter<Regular>("a", value: String($0))
            }, update: { _, _ in Issue.record("A different Input establishes a new association") }),
        ])

        #expect(change.hasStructuralChanges)
        #expect(change.retained.isEmpty)
        #expect(change.removed.first === previous)
        #expect(store.presenters.first !== previous)
        #expect((store.presenters.first as? Presenter<Regular>)?.value == "42")
    }

    @Test("Changes preserve target order for survivors and previous order for removals", arguments: [
        MembershipCase(target: ["a", "b", "c"], retained: ["a", "b", "c"], removed: [], structural: false),
        MembershipCase(target: ["c", "b", "a"], retained: ["c", "b", "a"], removed: [], structural: true),
        MembershipCase(target: ["c", "new", "a"], retained: ["c", "a"], removed: ["b"], structural: true),
        MembershipCase(target: ["new", "b"], retained: ["b"], removed: ["a", "c"], structural: true),
        MembershipCase(target: [], retained: [], removed: ["a", "b", "c"], structural: true),
    ])
    func membership(_ scenario: MembershipCase) throws {
        let store = SectionStore()
        try store.reconcile([definition("a"), definition("b"), definition("c")])
        let previous = Dictionary(uniqueKeysWithValues: zip(store.ids, store.presenters))

        let change = try store.reconcile(scenario.target.map { definition($0) })

        #expect(store.ids == scenario.target.map(AnyHashable.init))
        #expect(ids(change.presenters) == scenario.target)
        #expect(ids(change.retained) == scenario.retained)
        #expect(ids(change.removed) == scenario.removed)
        #expect(change.hasStructuralChanges == scenario.structural)
        for retained in change.retained {
            #expect(retained === previous[AnyHashable(retained.id)])
        }
    }

    @Test("Duplicate IDs reject the entire input before any side effect", arguments: [false, true])
    func duplicateIds(useAsync: Bool) async throws {
        let store = SectionStore()
        try store.reconcile([definition("a", value: "accepted")])
        let section = try #require(store.presenters.first as? Presenter<Regular>)
        let watched: (String) -> SectionDefinition = { id in
            SectionDefinition(id: id, input: "rejected", make: {
                Issue.record("Validation must finish before creating any instance")
                return Presenter<Regular>(id, value: $0)
            }, update: { _, _ in Issue.record("Validation must finish before updating any instance") })
        }
        // Both an insertion and a survivor precede the duplicate at the end.
        let definitions = [watched("new"), watched("a"), watched("duplicate"), watched("duplicate")]

        await #expect(throws: CollectionUpdateError.duplicateSectionId("duplicate")) {
            if useAsync {
                try await store.reconcile(definitions) { _ in Issue.record("Invalid membership must not be submitted") }
            } else {
                try store.reconcile(definitions)
            }
        }

        #expect(store.ids == [AnyHashable("a")])
        #expect(store.presenters.first === section)
        #expect(section.value == "accepted")
        try store.reconcile([definition("a", value: "valid retry")])
        #expect(section.value == "valid retry")
    }

    @Test("A removed identity gets a fresh instance when it returns")
    func reinsertion() throws {
        let store = SectionStore()
        try store.reconcile([definition("a")])
        let previous = try #require(store.presenters.first as? Presenter<Regular>)
        previous.isExpanded = true
        try store.reconcile([])
        let change = try store.reconcile([definition("a")])
        let replacement = try #require(store.presenters.first as? Presenter<Regular>)

        #expect(replacement !== previous)
        #expect(!replacement.isExpanded)
        #expect(change.retained.isEmpty)
        #expect(change.removed.isEmpty)
        #expect(change.hasStructuralChanges)
    }

    @Test("Store instances are independent even when they share definitions")
    func independentStores() throws {
        let first = SectionStore()
        let second = SectionStore()
        let definitions = [definition("a")]
        try first.reconcile(definitions)
        try second.reconcile(definitions)
        let a = try #require(first.presenters.first as? Presenter<Regular>)
        let b = try #require(second.presenters.first as? Presenter<Regular>)
        a.isExpanded = true

        #expect(a !== b)
        #expect(!b.isExpanded)
    }

    @Test("Inputs and closure captures are released after creation and reuse", arguments: [false, true])
    func releasesDefinitions(reuse: Bool) throws {
        let store = SectionStore()
        if reuse {
            try store.reconcile([
                SectionDefinition(id: "a", input: Reference(), make: { _ in
                    Presenter<Regular>("a", value: "initial")
                }, update: { _, _ in }),
            ])
        }
        let input = WeakReference()
        let factoryCapture = WeakReference()
        let updateCapture = WeakReference()
        do {
            let model = Reference()
            let factory = Reference()
            let updater = Reference()
            input.value = model
            factoryCapture.value = factory
            updateCapture.value = updater
            try store.reconcile([
                SectionDefinition(id: "a", input: model, make: { model in
                    Presenter<Regular>("a", value: factory.value + model.value)
                }, update: { section, model in
                    section.value = updater.value + model.value
                }),
            ])
        }

        #expect(input.value == nil)
        #expect(factoryCapture.value == nil)
        #expect(updateCapture.value == nil)
        #expect(store.presenters.count == 1)
    }

    @Test("A change retains removed presenters only for the lifetime of the result")
    func removalLifetime() throws {
        let store = SectionStore()
        try store.reconcile([definition("a")])
        let removed = try WeakReference(#require(store.presenters.first as? Presenter<Regular>))
        do {
            let change = try store.reconcile([])
            #expect(store.presenters.isEmpty)
            #expect(removed.value != nil)
            #expect(change.removed.first === removed.value)
        }
        #expect(removed.value == nil)
    }

    @Test("Releasing the store releases its remaining instances")
    func storeLifetime() throws {
        let reference = WeakReference()
        do {
            let store = SectionStore()
            try store.reconcile([definition("a")])
            reference.value = try #require(store.presenters.first as? Presenter<Regular>)
            #expect(reference.value != nil)
        }
        #expect(reference.value == nil)
    }

    @Test("Suspended submission keeps accepted membership until completion")
    func suspendedAcceptance() async throws {
        let store = SectionStore()
        try store.reconcile([definition("a", value: "old"), definition("b")])
        let a = try #require(store.presenters.first as? Presenter<Regular>)
        let gate = SubmissionGate()
        let submission = Task {
            try await store.reconcile([definition("new"), definition("a", value: "pending")]) { change in
                #expect(ids(change.presenters) == ["new", "a"])
                #expect(ids(change.removed) == ["b"])
                await gate.pause()
            }
        }
        await gate.waitUntilStarted()
        #expect(store.ids == [AnyHashable("a"), AnyHashable("b")])
        #expect(store.presenters.first === a)
        #expect(a.value == "pending")
        gate.resume()
        let change = try await submission.value

        #expect(store.ids == [AnyHashable("new"), AnyHashable("a")])
        #expect(store.presenters.last === a)
        #expect(change.retained.first === a)
    }

    @Test("Rejected structure preserves membership, not input mutations, and can be retried")
    func rejectedSubmission() async throws {
        let store = SectionStore()
        try store.reconcile([definition("a", value: "old"), definition("b")])
        let a = try #require(store.presenters.first as? Presenter<Regular>)
        let b = try #require(store.presenters.last)
        let rejected = WeakReference()

        await #expect(throws: Rejection.failed) {
            try await store.reconcile([definition("a", value: "pending"), definition("new")]) { change in
                rejected.value = change.presenters.last
                throw Rejection.failed
            }
        }

        #expect(store.ids == [AnyHashable("a"), AnyHashable("b")])
        #expect(store.presenters.first === a)
        #expect(store.presenters.last === b)
        #expect(a.value == "pending")
        #expect(rejected.value == nil)

        let retry = try await store.reconcile([definition("a", value: "retry"), definition("new")]) { change in
            #expect(change.retained.first === a)
            #expect(change.removed.first === b)
        }
        #expect(retry.hasStructuralChanges)
        #expect(store.ids == [AnyHashable("a"), AnyHashable("new")])
        #expect(a.value == "retry")
    }

    @Test("Cancellation thrown by the submitter rejects membership and releases candidates")
    func cancelledSubmission() async throws {
        let store = SectionStore()
        let rejected = WeakReference()
        await #expect(throws: CancellationError.self) {
            try await store.reconcile([definition("a")]) { change in
                rejected.value = change.presenters.first
                throw CancellationError()
            }
        }
        #expect(store.ids.isEmpty)
        #expect(rejected.value == nil)
        try await store.reconcile([definition("a")]) { _ in }
        #expect(store.ids == [AnyHashable("a")])
    }

    private func definition(_ id: String, value: String = "value") -> SectionDefinition {
        SectionDefinition(id: id, input: value, make: {
            Presenter<Regular>(id, value: $0)
        }, update: { $0.value = $1 })
    }

    private func ids(_ presenters: [any SectionPresenter]) -> [String] {
        presenters.map { String(describing: $0.id) }
    }
}

struct MembershipCase {
    let target: [String]
    let retained: [String]
    let removed: [String]
    let structural: Bool
}

private enum Regular {}
private enum Featured {}
private enum Rejection: Error { case failed }

@MainActor
private final class Presenter<Kind>: SectionPresenter {
    let id: String
    let updates = SectionUpdateContext()
    var value: String
    var isExpanded = false

    init(_ id: String, value: String) {
        self.id = id
        self.value = value
    }

    func captureContent() -> DefaultSectionContent {
        Issue.record("SectionStore must not capture or submit a presentation")
        return testSectionContent(cells: [])
    }
}

private final class Reference {
    let value = "reference"
}

private final class WeakReference {
    weak var value: AnyObject?
    init(_ value: AnyObject? = nil) {
        self.value = value
    }
}

@MainActor
private final class SubmissionGate {
    private let started = AsyncStream<Void>.makeStream()
    private var continuation: CheckedContinuation<Void, Never>?

    func pause() async {
        await withCheckedContinuation {
            continuation = $0
            started.continuation.yield(())
            started.continuation.finish()
        }
    }

    func waitUntilStarted() async {
        for await _ in started.stream {
            return
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
