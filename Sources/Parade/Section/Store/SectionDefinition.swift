// Created by weixi on 2026/09/23.

import Foundation

/// One section's identity, input, and construction/update behavior for a reconciliation.
///
/// A store reuses an instance only when its ID, Input type, and Presenter type all
/// match. Changing either type replaces the instance, even under the same ID.
/// Each reconciliation uses the current definition's closures. Inputs need not be
/// Equatable: every retained instance receives its input, even if it appears unchanged.
@MainActor
public struct SectionDefinition {
    public let id: AnyHashable

    /// `make` receives the initial input; `update` runs only for a retained instance.
    /// Both must preserve the supplied ID. Use `update` to stage business state;
    /// presentation submission remains the caller's responsibility.
    public init<Id: Hashable, Input, Presenter: SectionPresenter>(
        id: Id,
        input: Input,
        make: @escaping @MainActor (Input) -> Presenter,
        update: @escaping @MainActor (Presenter, Input) -> Void
    ) where Presenter.Id == Id {
        self.id = AnyHashable(id)
        resolve = { previous in
            if let previous = previous as? SectionInstance<Input, Presenter> {
                update(previous.value, input)
                precondition(previous.value.id == id, "Updating a section must preserve its ID")
                return previous
            }

            let presenter = make(input)
            precondition(presenter.id == id, "Section and presenter IDs must match")
            return SectionInstance<Input, Presenter>(presenter)
        }
    }

    let resolve: @MainActor ((any StoredSection)?) -> any StoredSection
}

@MainActor
protocol StoredSection: AnyObject {
    var id: AnyHashable { get }
    var presenter: any SectionPresenter { get }
}

/// Retains the presenter and its type association, never an input or definition closure.
@MainActor
private final class SectionInstance<Input, Presenter: SectionPresenter>: StoredSection {
    let id: AnyHashable
    let value: Presenter

    init(_ value: Presenter) {
        id = AnyHashable(value.id)
        self.value = value
    }

    var presenter: any SectionPresenter {
        value
    }
}
