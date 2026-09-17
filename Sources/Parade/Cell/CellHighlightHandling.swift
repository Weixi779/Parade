//
//  CellHighlightHandling.swift
//  Parade
//
//  Created by weixi on 2026/9/17.
//

import UIKit

/// Opts a cell presenter into highlighting policy and callbacks.
/// Without this conformance, Parade permits highlighting without presenter callbacks.
public protocol CellHighlightHandling<Cell>: CellPresenter {
    @MainActor var shouldHighlight: Bool { get }
    @MainActor func didHighlight(_ cell: Cell)
    @MainActor func didUnhighlight(_ cell: Cell)
}

public extension CellHighlightHandling {
    var shouldHighlight: Bool { true }
    func didHighlight(_ cell: Cell) {}
    func didUnhighlight(_ cell: Cell) {}
}

@MainActor
extension CellHighlightHandling {
    func dispatchHighlight(to rawCell: UICollectionViewCell) {
        guard let cell = rawCell as? Cell else { return }
        didHighlight(cell)
    }

    func dispatchUnhighlight(to rawCell: UICollectionViewCell) {
        guard let cell = rawCell as? Cell else { return }
        didUnhighlight(cell)
    }
}

@MainActor
public extension AnyCellPresenter {
    /// Reads the current policy from the underlying presenter, defaulting to true.
    var shouldHighlight: Bool {
        (underlyingPresenter as? any CellHighlightHandling)?.shouldHighlight ?? true
    }
}
