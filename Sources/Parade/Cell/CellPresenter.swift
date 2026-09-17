//
//  CellPresenter.swift
//  Parade
//
//  Created by weixi on 2026/9/17.
//

import UIKit

/// An immutable presentation of one cell occurrence.
///
/// IDs must be unique across the collection. Keep submitted presenters unchanged:
/// Parade retains them for content comparison and callbacks. Content equality
/// describes visual content, independently of identity and behavior closures.
/// Opt into interaction and visibility callbacks through the capability protocols.
public protocol CellPresenter: DiffableElement {
    associatedtype Cell: UICollectionViewCell

    @MainActor func configure(_ cell: Cell)

    /// Replace this presenter's behavior bindings, including existing actions.
    ///
    /// Parade invokes this even when visual content is equal. Implementations
    /// should replace their own bindings rather than append duplicate targets.
    /// Presenters sharing a cell type must overwrite or clear bindings they own;
    /// the default no-op does not remove actions installed by a previous presenter.
    @MainActor func setBehaviors(_ cell: Cell)
}

public extension CellPresenter {
    func setBehaviors(_ cell: Cell) {}
}

@MainActor
extension CellPresenter {
    func configureErased(_ rawCell: UICollectionViewCell) {
        guard let cell = rawCell as? Cell else { return }
        configure(cell)
    }

    func setBehaviorsErased(_ rawCell: UICollectionViewCell) {
        guard let cell = rawCell as? Cell else { return }
        setBehaviors(cell)
    }
}
