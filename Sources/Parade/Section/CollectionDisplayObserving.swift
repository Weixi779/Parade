// Created by weixi on 2026/09/23.

/// Observes the whole collection's display lifecycle, even when this section is offscreen.
/// The application supplies visibility through CollectionOrchestrator.isVisible.
@MainActor
public protocol CollectionDisplayObserving: SectionController {
    /// The collection is visible and this module has completed attachment.
    func collectionWillDisplay()

    /// The collection became hidden, or this module is being detached.
    func collectionDidEndDisplaying()
}

public extension CollectionDisplayObserving {
    func collectionWillDisplay() {}
    func collectionDidEndDisplaying() {}
}
