//
//  AnySupplementaryPresenter.swift
//  Parade
//
//  Created by weixi on 2026/9/17.
//

import UIKit

/// A supplementary presenter erased at the section's composition boundary.
/// Preserves the original presenter so internal consumers can discover capabilities.
public struct AnySupplementaryPresenter: DiffableElement {
    public let id: AnyHashable
    public let elementKind: String
    public let itemIndex: Int

    let underlyingPresenter: any SupplementaryPresenter
    let registrationKey: RegistrationKey

    @MainActor
    public init<P: SupplementaryPresenter>(_ presenter: P) {
        id = AnyHashable(presenter.id)
        elementKind = presenter.elementKind
        itemIndex = presenter.itemIndex
        registrationKey = RegistrationKey(
            viewType: P.View.self,
            elementKind: elementKind
        )
        underlyingPresenter = presenter
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.underlyingPresenter.equals(rhs.underlyingPresenter)
    }

    @MainActor
    func configure(_ view: UICollectionReusableView) {
        underlyingPresenter.configureErased(view)
    }

    @MainActor
    func setBehaviors(_ view: UICollectionReusableView) {
        underlyingPresenter.setBehaviorsErased(view)
    }
}
