//
//  SupplementaryPresenter.swift
//  Parade
//
//  Created by weixi on 2026/9/17.
//

import UIKit

/// An immutable presentation of a header, footer, or custom supplementary view.
///
/// The section, element kind, and item index identify its layout address. Its
/// Id identifies the logical presentation at that address. The application's
/// layout is responsible for requesting the corresponding kind and index.
/// Opt into view visibility callbacks through `SupplementaryDisplayObserving`.
public protocol SupplementaryPresenter: Equatable {
    associatedtype Id: Hashable
    associatedtype View: UICollectionReusableView

    var id: Id { get }
    @MainActor var elementKind: String { get }
    var itemIndex: Int { get }
    @MainActor func configure(_ view: View)

    /// Replace bindings even when visual content is equal. Presenters sharing a
    /// view type must overwrite or clear bindings they own; the default no-op
    /// does not remove actions installed by a previous presenter.
    @MainActor func bind(to view: View)
}

public extension SupplementaryPresenter {
    @MainActor static var headerKind: String { UICollectionView.elementKindSectionHeader }
    @MainActor static var footerKind: String { UICollectionView.elementKindSectionFooter }
    var itemIndex: Int { 0 }
    func bind(to view: View) {}
}

extension SupplementaryPresenter {
    func equals(_ other: any SupplementaryPresenter) -> Bool {
        guard type(of: self) == type(of: other), let other = other as? Self else { return false }
        return self == other
    }
}

@MainActor
extension SupplementaryPresenter {
    func configureErased(_ rawView: UICollectionReusableView) {
        guard let view = rawView as? View else { return }
        configure(view)
    }

    func bindErased(to rawView: UICollectionReusableView) {
        guard let view = rawView as? View else { return }
        bind(to: view)
    }
}
