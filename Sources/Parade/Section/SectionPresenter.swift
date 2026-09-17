//
//  SectionPresenter.swift
//  Parade
//
//  Created by weixi on 2026/9/17.
//

/// The current presentation of one collection section.
///
/// A section can contain any number of cell types, including no cells. The
/// application owns its state; Parade captures its composition when submitted.
public protocol SectionPresenter {
    associatedtype Id: Hashable

    var id: Id { get }
    @MainActor var cells: [AnyCellPresenter] { get }
    @MainActor var supplementaryViews: [AnySupplementaryPresenter] { get }
}

public extension SectionPresenter {
    @MainActor var supplementaryViews: [AnySupplementaryPresenter] { [] }
}
