//
//  AnyCellPresenter.swift
//  Parade
//
//  Created by weixi on 2026/9/17.
//

import UIKit

/// A cell presenter erased only at the section's composition boundary.
/// Preserves the original presenter so internal consumers can discover capabilities.
public struct AnyCellPresenter: DiffableElement {
    public let id: AnyHashable

    let underlyingPresenter: any CellPresenter
    let registrationKey: RegistrationKey

    public init<P: CellPresenter>(_ presenter: P) {
        id = AnyHashable(presenter.id)
        registrationKey = RegistrationKey(viewType: P.Cell.self)
        underlyingPresenter = presenter
    }

    /// Compares visual content when both erasers contain the same presenter type.
    /// Identity and registration compatibility are compared separately by Parade.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.underlyingPresenter.equals(rhs.underlyingPresenter)
    }

    @MainActor
    func configure(_ cell: UICollectionViewCell) {
        underlyingPresenter.configureErased(cell)
    }

    @MainActor
    func setBehaviors(_ cell: UICollectionViewCell) {
        underlyingPresenter.setBehaviorsErased(cell)
    }
}
