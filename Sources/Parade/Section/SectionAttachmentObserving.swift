// Created by weixi on 2026/09/22.

/// Observes successful membership changes, independently of view visibility.
@MainActor
public protocol SectionAttachmentObserving: SectionPresenter {
    /// The update context is attached and can accept updates.
    func didAttach()
    /// The update context is disconnected. Cancel work owned by this attachment.
    /// On orchestrator destruction, this runs in a subsequent MainActor task.
    func didDetach()
}

public extension SectionAttachmentObserving {
    func didAttach() {}
    func didDetach() {}
}
