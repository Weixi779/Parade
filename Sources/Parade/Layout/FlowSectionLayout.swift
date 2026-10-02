// Created by weixi on 2026/10/02.

import UIKit

/// A captured section's native Flow delegate factory. Copy mutable business inputs
/// before creating this value; the factory must not reread a live section owner.
/// Create a fresh value for each capture. The delegate is built lazily, retained
/// with this value, and reused while queried through the same collection access.
@MainActor
public final class FlowSectionLayout {
    private let makeDelegate: (LayoutAccess<FlowSectionLayout>) -> any UICollectionViewDelegateFlowLayout
    private weak var boundAccess: LayoutAccess<FlowSectionLayout>?
    private var boundDelegate: (any UICollectionViewDelegateFlowLayout)?

    public init(
        _ makeDelegate: @escaping (LayoutAccess<FlowSectionLayout>) -> some UICollectionViewDelegateFlowLayout
    ) {
        self.makeDelegate = makeDelegate
    }

    fileprivate func delegate(in access: LayoutAccess<FlowSectionLayout>) -> any UICollectionViewDelegateFlowLayout {
        if boundAccess === access, let boundDelegate {
            return boundDelegate
        }
        let delegate = makeDelegate(access)
        boundAccess = access
        boundDelegate = delegate
        return delegate
    }
}

public extension CollectionLayout where Layout == FlowSectionLayout {
    /// Supply a fresh layout for each collection. A custom Flow subclass retains
    /// control over attributes, invalidation and animations.
    static func flow(_ layout: UICollectionViewFlowLayout = UICollectionViewFlowLayout()) -> Self {
        Self(
            makeLayout: { _ in layout },
            makeDelegate: { access in
                FlowLayoutDelegate(access: access)
            }
        )
    }
}

private final class FlowLayoutDelegate: CollectionLayoutDelegate, UICollectionViewDelegateFlowLayout {
    private let access: LayoutAccess<FlowSectionLayout>

    init(access: LayoutAccess<FlowSectionLayout>) {
        self.access = access
        super.init()
    }

    private func delegate(at section: Int) -> (any UICollectionViewDelegateFlowLayout)? {
        access.section(at: section)?.layoutValue.delegate(in: access)
    }

    func collectionView(
        _ view: UICollectionView,
        layout: UICollectionViewLayout,
        sizeForItemAt path: IndexPath
    ) -> CGSize {
        delegate(at: path.section)?.collectionView?(view, layout: layout, sizeForItemAt: path)
            ?? (layout as? UICollectionViewFlowLayout)?.itemSize ?? .zero
    }

    func collectionView(
        _ view: UICollectionView,
        layout: UICollectionViewLayout,
        insetForSectionAt section: Int
    ) -> UIEdgeInsets {
        delegate(at: section)?.collectionView?(view, layout: layout, insetForSectionAt: section)
            ?? (layout as? UICollectionViewFlowLayout)?.sectionInset ?? .zero
    }

    func collectionView(
        _ view: UICollectionView,
        layout: UICollectionViewLayout,
        minimumLineSpacingForSectionAt section: Int
    ) -> CGFloat {
        delegate(at: section)?.collectionView?(view, layout: layout, minimumLineSpacingForSectionAt: section)
            ?? (layout as? UICollectionViewFlowLayout)?.minimumLineSpacing ?? 0
    }

    func collectionView(
        _ view: UICollectionView,
        layout: UICollectionViewLayout,
        minimumInteritemSpacingForSectionAt section: Int
    ) -> CGFloat {
        delegate(at: section)?.collectionView?(view, layout: layout, minimumInteritemSpacingForSectionAt: section)
            ?? (layout as? UICollectionViewFlowLayout)?.minimumInteritemSpacing ?? 0
    }

    func collectionView(
        _ view: UICollectionView,
        layout: UICollectionViewLayout,
        referenceSizeForHeaderInSection section: Int
    ) -> CGSize {
        delegate(at: section)?.collectionView?(view, layout: layout, referenceSizeForHeaderInSection: section)
            ?? (layout as? UICollectionViewFlowLayout)?.headerReferenceSize ?? .zero
    }

    func collectionView(
        _ view: UICollectionView,
        layout: UICollectionViewLayout,
        referenceSizeForFooterInSection section: Int
    ) -> CGSize {
        delegate(at: section)?.collectionView?(view, layout: layout, referenceSizeForFooterInSection: section)
            ?? (layout as? UICollectionViewFlowLayout)?.footerReferenceSize ?? .zero
    }
}
