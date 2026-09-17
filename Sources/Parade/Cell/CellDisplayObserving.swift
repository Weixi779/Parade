//
//  CellDisplayObserving.swift
//  Parade
//
//  Created by weixi on 2026/9/17.
//

import UIKit

/// Opts a cell presenter into view visibility callbacks.
/// These callbacks do not define the item's lifetime or own asynchronous work.
public protocol CellDisplayObserving<Cell>: CellPresenter {
    @MainActor func willDisplay(_ cell: Cell)
    @MainActor func didEndDisplaying(_ cell: Cell)
}

public extension CellDisplayObserving {
    func willDisplay(_ cell: Cell) {}
    func didEndDisplaying(_ cell: Cell) {}
}

@MainActor
extension CellDisplayObserving {
    func dispatchWillDisplay(to rawCell: UICollectionViewCell) {
        guard let cell = rawCell as? Cell else { return }
        willDisplay(cell)
    }

    func dispatchDidEndDisplaying(to rawCell: UICollectionViewCell) {
        guard let cell = rawCell as? Cell else { return }
        didEndDisplaying(cell)
    }
}
