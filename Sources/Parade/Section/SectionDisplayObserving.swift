// Created by weixi on 2026/09/23.

/// Observes whether an attached section has displayed content in a visible collection.
/// Cells and supplementary views both count; prepared views do not. This does not
/// measure exposure percentages, occlusion, or application activity. During content
/// updates, notifications wait until all UIKit stages have settled.
@MainActor
public protocol SectionDisplayObserving: SectionPresenter {
    /// The first view begins displaying, or the collection becomes visible while
    /// this section already has displayed views. Runs after collectionWillDisplay().
    func sectionWillDisplay()

    /// The last view ends displaying, the collection becomes hidden, or this module
    /// is being detached. Runs before collectionDidEndDisplaying() and didDetach().
    func sectionDidEndDisplaying()
}

public extension SectionDisplayObserving {
    func sectionWillDisplay() {}
    func sectionDidEndDisplaying() {}
}
