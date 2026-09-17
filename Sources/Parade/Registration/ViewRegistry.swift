//
//  ViewRegistry.swift
//  Parade
//
//  Created by weixi on 2026/9/17.
//

import UIKit

/// Owns the native registrations for one orchestrator's collection view.
@MainActor
final class ViewRegistry {
    private var cellRegistrations: [RegistrationKey: Any] = [:]
    private var supplementaryRegistrations: [RegistrationKey: Any] = [:]

    func cell(
        for presenter: AnyCellPresenter,
        in collectionView: UICollectionView,
        at indexPath: IndexPath
    ) -> UICollectionViewCell {
        dequeueCell(
            for: presenter.underlyingPresenter,
            presenter: presenter,
            in: collectionView,
            at: indexPath
        )
    }

    func supplementary(
        for presenter: AnySupplementaryPresenter,
        in collectionView: UICollectionView,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        dequeueSupplementary(
            for: presenter.underlyingPresenter,
            presenter: presenter,
            in: collectionView,
            at: indexPath
        )
    }

    /// UIKit registrations must be created before entering a data-source callback.
    func prepare(_ presenter: AnyCellPresenter) {
        prepareCell(for: presenter.underlyingPresenter)
    }

    func prepare(_ presenter: AnySupplementaryPresenter) {
        prepareSupplementary(for: presenter.underlyingPresenter, elementKind: presenter.elementKind)
    }

    private func prepareCell<P: CellPresenter>(for presenter: P) {
        _ = cellRegistration(P.Cell.self)
    }

    private func prepareSupplementary<P: SupplementaryPresenter>(
        for presenter: P,
        elementKind: String
    ) {
        _ = supplementaryRegistration(P.View.self, elementKind: elementKind)
    }

    private func dequeueCell<P: CellPresenter>(
        for underlyingPresenter: P,
        presenter: AnyCellPresenter,
        in collectionView: UICollectionView,
        at indexPath: IndexPath
    ) -> UICollectionViewCell {
        let native = cellRegistration(P.Cell.self)
        return collectionView.dequeueConfiguredReusableCell(
            using: native,
            for: indexPath,
            item: presenter
        )
    }

    private func dequeueSupplementary<P: SupplementaryPresenter>(
        for underlyingPresenter: P,
        presenter: AnySupplementaryPresenter,
        in collectionView: UICollectionView,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        let native = supplementaryRegistration(P.View.self, elementKind: presenter.elementKind)
        let view = collectionView.dequeueConfiguredReusableSupplementary(
            using: native,
            for: indexPath
        )
        presenter.configure(view)
        presenter.setBehaviors(view)
        return view
    }

    private func cellRegistration<Cell: UICollectionViewCell>(
        _ cellType: Cell.Type
    ) -> UICollectionView.CellRegistration<Cell, AnyCellPresenter> {
        let key = RegistrationKey(viewType: cellType)
        if let cached = cellRegistrations[key] as? UICollectionView.CellRegistration<Cell, AnyCellPresenter> {
            return cached
        }
        let native = UICollectionView.CellRegistration<Cell, AnyCellPresenter> { cell, _, current in
            current.configure(cell)
            current.setBehaviors(cell)
        }
        cellRegistrations[key] = native
        return native
    }

    private func supplementaryRegistration<View: UICollectionReusableView>(
        _ viewType: View.Type,
        elementKind: String
    ) -> UICollectionView.SupplementaryRegistration<View> {
        let key = RegistrationKey(viewType: viewType, elementKind: elementKind)
        if let cached = supplementaryRegistrations[key] as? UICollectionView.SupplementaryRegistration<View> {
            return cached
        }
        // SupplementaryRegistration has no item parameter. Its handler stays
        // stateless; configure using the supplied presenter after dequeue.
        let native = UICollectionView.SupplementaryRegistration<View>(
            elementKind: elementKind
        ) { _, _, _ in }
        supplementaryRegistrations[key] = native
        return native
    }
}
