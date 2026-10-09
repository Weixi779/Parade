// Created by weixi on 2026/09/23.

import Foundation

/// One section's identity, input, and construction/update behavior for a reconciliation.
///
/// A store reuses an instance only when its ID, Input type, and Controller type all
/// match. Changing either type replaces the instance, even under the same ID.
/// Typed input definitions use the current closures and apply even unchanged input;
/// inputs need not be Equatable. Store-provided retaining definitions keep the instance
/// without applying an input or invoking an updater.
@MainActor
public struct SectionDefinition<Layout> {
    public let id: AnyHashable

    /// `make` receives the initial input; `update` runs only for a retained instance.
    /// Both must preserve the supplied ID. Use `update` to stage business state;
    /// presentation submission remains the caller's responsibility.
    public init<Id: Hashable, Input, Controller: SectionController<Layout>>(
        id: Id,
        input: Input,
        make: @escaping @MainActor (Input) -> Controller,
        update: @escaping @MainActor (Controller, Input) -> Void
    ) where Controller.Id == Id {
        self.id = AnyHashable(id)
        resolve = { previous in
            if let previous = previous as? SectionInstance<Layout, Input, Controller> {
                update(previous.value, input)
                precondition(previous.value.id == id, "Updating a section must preserve its ID")
                return previous
            }

            let controller = make(input)
            precondition(controller.id == id, "Section and controller IDs must match")
            return SectionInstance<Layout, Input, Controller>(controller)
        }
    }

    /// Keeps the stored type association without retaining or replaying an old input.
    init(retaining instance: any StoredSection<Layout>) {
        id = instance.id
        resolve = { _ in instance }
    }

    let resolve: @MainActor ((any StoredSection<Layout>)?) -> any StoredSection<Layout>
}

@MainActor
protocol StoredSection<Layout>: AnyObject {
    associatedtype Layout
    var id: AnyHashable { get }
    var controller: any SectionController<Layout> { get }
}

/// Retains the controller and its type association, never an input or definition closure.
@MainActor
private final class SectionInstance<Layout, Input, Controller: SectionController<Layout>>: StoredSection {
    let id: AnyHashable
    let value: Controller

    init(_ value: Controller) {
        id = AnyHashable(value.id)
        self.value = value
    }

    var controller: any SectionController<Layout> {
        value
    }
}
