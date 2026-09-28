// Created by weixi on 2026/10/02.

import UIKit

/// Experiment: each layout integration declares its section payload type.
@MainActor
public struct CollectionLayout<Layout> {
    let makeLayout: (LayoutAccess<Layout>) -> UICollectionViewLayout
    let makeDelegate: (UICollectionView, LayoutAccess<Layout>) -> CollectionViewBridge<Layout>

    public init(
        makeLayout: @escaping (LayoutAccess<Layout>) -> UICollectionViewLayout,
        makeDelegate: @escaping (UICollectionView, LayoutAccess<Layout>) -> CollectionViewBridge<Layout>
    ) {
        self.makeLayout = makeLayout
        self.makeDelegate = makeDelegate
    }
}

@MainActor
public final class LayoutAccess<Layout> {
    weak var owner: CollectionOrchestrator<Layout>?

    public func section(at index: Int) -> SectionSnapshot<Layout>? {
        owner?.source.sectionSnapshot(at: index)
    }

    public func item<P: CellPresenter>(at indexPath: IndexPath, as type: P.Type) -> P? {
        owner?.cellPresenter(at: indexPath)?.underlyingPresenter as? P
    }

    public func indexPath<Id: Hashable>(for id: Id) -> IndexPath? {
        owner?.indexPath(for: id)
    }
}

/// A concrete return value builder. Section code still creates native layout sections.
public struct CompositionalSectionLayout {
    let build: @MainActor (NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection

    public init(_ build: @escaping @MainActor (NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection) {
        self.build = build
    }
}

public extension CollectionLayout where Layout == CompositionalSectionLayout {
    static func compositional() -> Self {
        Self(makeLayout: { access in
            UICollectionViewCompositionalLayout { index, environment in
                access.section(at: index)?.layoutValue.build(environment)
            }
        }, makeDelegate: { view, _ in CollectionViewBridge(collectionView: view) })
    }
}

/// Its generic initializer retains a concrete native delegate through this family's
/// query functions. It does not add a central list of other layout capabilities.
@MainActor
public final class FlowSectionLayout {
    private let build: (LayoutAccess<FlowSectionLayout>) -> Queries
    private var cached: Queries?
    private weak var cachedAccess: LayoutAccess<FlowSectionLayout>?

    public init<D: UICollectionViewDelegateFlowLayout>(
        _ make: @escaping (LayoutAccess<FlowSectionLayout>) -> D
    ) {
        build = { access in
            let delegate = make(access)
            return Queries(
                size: { view, layout, path in
                    delegate.collectionView?(view, layout: layout, sizeForItemAt: path) ?? layout.itemSize
                },
                insets: { view, layout, section in
                    delegate.collectionView?(view, layout: layout, insetForSectionAt: section) ?? layout.sectionInset
                },
                lineSpacing: { view, layout, section in
                    delegate.collectionView?(view, layout: layout, minimumLineSpacingForSectionAt: section) ?? layout.minimumLineSpacing
                },
                itemSpacing: { view, layout, section in
                    delegate.collectionView?(view, layout: layout, minimumInteritemSpacingForSectionAt: section) ?? layout.minimumInteritemSpacing
                },
                header: { view, layout, section in
                    delegate.collectionView?(view, layout: layout, referenceSizeForHeaderInSection: section) ?? layout.headerReferenceSize
                },
                footer: { view, layout, section in
                    delegate.collectionView?(view, layout: layout, referenceSizeForFooterInSection: section) ?? layout.footerReferenceSize
                }
            )
        }
    }

    fileprivate struct Queries {
        let size: (UICollectionView, UICollectionViewFlowLayout, IndexPath) -> CGSize
        let insets: (UICollectionView, UICollectionViewFlowLayout, Int) -> UIEdgeInsets
        let lineSpacing: (UICollectionView, UICollectionViewFlowLayout, Int) -> CGFloat
        let itemSpacing: (UICollectionView, UICollectionViewFlowLayout, Int) -> CGFloat
        let header: (UICollectionView, UICollectionViewFlowLayout, Int) -> CGSize
        let footer: (UICollectionView, UICollectionViewFlowLayout, Int) -> CGSize
    }

    fileprivate func queries(_ access: LayoutAccess<FlowSectionLayout>) -> Queries {
        if cachedAccess === access, let cached { return cached }
        let result = build(access)
        cachedAccess = access
        cached = result
        return result
    }
}

public extension CollectionLayout where Layout == FlowSectionLayout {
    static func flow(_ layout: UICollectionViewFlowLayout = UICollectionViewFlowLayout()) -> Self {
        Self(makeLayout: { _ in layout }, makeDelegate: { view, access in
            FlowBridge(collectionView: view, access: access)
        })
    }
}

private final class FlowBridge: CollectionViewBridge<FlowSectionLayout>, UICollectionViewDelegateFlowLayout {
    private let access: LayoutAccess<FlowSectionLayout>

    init(collectionView: UICollectionView, access: LayoutAccess<FlowSectionLayout>) {
        self.access = access
        super.init(collectionView: collectionView)
    }

    func collectionView(_ view: UICollectionView, layout raw: UICollectionViewLayout, sizeForItemAt path: IndexPath) -> CGSize {
        guard let layout = raw as? UICollectionViewFlowLayout else { return .zero }
        return access.section(at: path.section)?.layoutValue.queries(access).size(view, layout, path) ?? layout.itemSize
    }

    func collectionView(_ view: UICollectionView, layout raw: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        guard let layout = raw as? UICollectionViewFlowLayout else { return .zero }
        return access.section(at: section)?.layoutValue.queries(access).insets(view, layout, section) ?? layout.sectionInset
    }

    func collectionView(_ view: UICollectionView, layout raw: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        guard let layout = raw as? UICollectionViewFlowLayout else { return 0 }
        return access.section(at: section)?.layoutValue.queries(access).lineSpacing(view, layout, section) ?? layout.minimumLineSpacing
    }

    func collectionView(_ view: UICollectionView, layout raw: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        guard let layout = raw as? UICollectionViewFlowLayout else { return 0 }
        return access.section(at: section)?.layoutValue.queries(access).itemSpacing(view, layout, section) ?? layout.minimumInteritemSpacing
    }

    func collectionView(_ view: UICollectionView, layout raw: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        guard let layout = raw as? UICollectionViewFlowLayout else { return .zero }
        return access.section(at: section)?.layoutValue.queries(access).header(view, layout, section) ?? layout.headerReferenceSize
    }

    func collectionView(_ view: UICollectionView, layout raw: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize {
        guard let layout = raw as? UICollectionViewFlowLayout else { return .zero }
        return access.section(at: section)?.layoutValue.queries(access).footer(view, layout, section) ?? layout.footerReferenceSize
    }
}
