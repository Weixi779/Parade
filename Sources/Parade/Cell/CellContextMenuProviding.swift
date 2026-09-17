//
//  CellContextMenuProviding.swift
//  Parade
//
//  Created by weixi on 2026/9/17.
//

import UIKit

/// Opts a cell presenter into providing a context menu for its concrete cell type.
public protocol CellContextMenuProviding<Cell>: CellPresenter {
    @MainActor func contextMenuConfiguration(for cell: Cell, at point: CGPoint) -> UIContextMenuConfiguration?
}

@MainActor
extension CellContextMenuProviding {
    func dispatchContextMenu(
        for rawCell: UICollectionViewCell,
        at point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let cell = rawCell as? Cell else { return nil }
        return contextMenuConfiguration(for: cell, at: point)
    }
}
