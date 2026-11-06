// Created by weixi on 2026/11/06.

/// Typed access to an ordered membership of live section instances.
/// Queries do not imply attachment, visibility, or presentation delivery.
@MainActor
public protocol SectionControllerQuery<Layout> {
    associatedtype Layout

    /// Returns nil when the ID is absent or its instance has a different controller type.
    func controller<Controller: SectionController<Layout>>(
        for id: Controller.Id,
        as type: Controller.Type
    ) -> Controller?

    /// Returns matching instances in membership order.
    func controllers<Controller: SectionController<Layout>>(
        ofType type: Controller.Type
    ) -> [Controller]
}

public extension SectionControllerQuery {
    /// Infers the controller type from the result's context.
    func controller<Controller: SectionController<Layout>>(
        for id: Controller.Id
    ) -> Controller? {
        controller(for: id, as: Controller.self)
    }
}
