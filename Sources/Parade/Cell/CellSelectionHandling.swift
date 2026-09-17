//
//  CellSelectionHandling.swift
//  Parade
//
//  Created by weixi on 2026/9/17.
//

import UIKit

/// Opts a cell presenter into selection policy and callbacks.
///
/// Without this conformance, Parade permits selection and deselection but delivers
/// no presenter callbacks. Collection-wide event handling remains available.
public protocol CellSelectionHandling<Cell>: CellPresenter {
    @MainActor var shouldSelect: Bool { get }
    @MainActor var shouldDeselect: Bool { get }
    @MainActor func didSelect(_ cell: Cell)
    @MainActor func didDeselect(_ cell: Cell)
}

public extension CellSelectionHandling {
    var shouldSelect: Bool { true }
    var shouldDeselect: Bool { true }
    func didSelect(_ cell: Cell) {}
    func didDeselect(_ cell: Cell) {}
}

@MainActor
extension CellSelectionHandling {
    func dispatchSelection(to rawCell: UICollectionViewCell) {
        guard let cell = rawCell as? Cell else { return }
        didSelect(cell)
    }

    func dispatchDeselection(to rawCell: UICollectionViewCell) {
        guard let cell = rawCell as? Cell else { return }
        didDeselect(cell)
    }
}

@MainActor
public extension AnyCellPresenter {
    /// Reads the current policy from the underlying presenter, defaulting to true.
    var shouldSelect: Bool {
        (underlyingPresenter as? any CellSelectionHandling)?.shouldSelect ?? true
    }

    /// Reads the current policy from the underlying presenter, defaulting to true.
    var shouldDeselect: Bool {
        (underlyingPresenter as? any CellSelectionHandling)?.shouldDeselect ?? true
    }
}
