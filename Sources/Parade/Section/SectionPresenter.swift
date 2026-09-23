// Created by weixi on 2026/09/21.

import Foundation

/// A stable business module corresponding to one UICollectionView section.
/// Own requests and listeners here; submit immutable display versions with update().
@MainActor
public protocol SectionPresenter: AnyObject {
    associatedtype Id: Hashable
    associatedtype Content: SectionContent

    var id: Id { get }
    var updates: SectionUpdateContext { get }
    func captureContent() -> Content
}

public extension SectionPresenter {
    /// Captures now, then awaits this operation's content, layout and binding updates.
    func update(animated: Bool = true, mode: CollectionUpdateMode = .diff) async throws {
        try await updates.update(animated: animated, mode: mode)
    }
}

/// Own one context per section instance. The collection binds it on successful
/// attachment and disconnects it on removal. It never retains the collection.
@MainActor
public final class SectionUpdateContext {
    public init() {}

    public var isAttached: Bool { owner != nil && submit != nil }
    weak var owner: AnyObject?
    var submit: (@MainActor (Bool, CollectionUpdateMode) async throws -> Void)?

    public func update(animated: Bool = true, mode: CollectionUpdateMode = .diff) async throws {
        guard isAttached, let submit else { throw CollectionUpdateError.sectionNotAttached }
        try await submit(animated, mode)
    }

    func disconnect(from owner: AnyObject) {
        guard self.owner === owner else { return }
        self.owner = nil
        submit = nil
    }
}
