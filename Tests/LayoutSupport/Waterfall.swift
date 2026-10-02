// Created by weixi on 2026/10/02.

import Parade
import UIKit

/// This protocol and layout live outside Parade. Parade does not know their methods.
@MainActor public protocol WaterfallDelegate: AnyObject {
    func columns(in section: Int) -> Int
    func height(at path: IndexPath, width: CGFloat) -> CGFloat
}

public final class WaterfallLayout: UICollectionViewLayout {
    private var attributes: [IndexPath: UICollectionViewLayoutAttributes] = [:]
    private var size: CGSize = .zero
    override public func prepare() {
        super.prepare()
        guard let view = collectionView, let delegate = view.delegate as? WaterfallDelegate else {
            return
        }
        attributes.removeAll()
        var y: CGFloat = 12
        for section in 0 ..< view.numberOfSections {
            let columns = max(1, delegate.columns(in: section))
            let width = floor((view.bounds.width - 32 - CGFloat(columns - 1) * 10) / CGFloat(columns))
            var bottoms = Array(repeating: y, count: columns)
            for item in 0 ..< view.numberOfItems(inSection: section) {
                let column = bottoms.indices.min { bottoms[$0] < bottoms[$1] }!
                let path = IndexPath(item: item, section: section)
                let attribute = UICollectionViewLayoutAttributes(forCellWith: path)
                attribute.frame = CGRect(
                    x: 16 + CGFloat(column) * (width + 10),
                    y: bottoms[column],
                    width: width,
                    height: delegate.height(at: path, width: width)
                )
                attributes[path] = attribute
                bottoms[column] = attribute.frame.maxY + 10
            }
            y = (bottoms.max() ?? y) + 12
        }
        size = CGSize(width: view.bounds.width, height: y)
    }

    override public var collectionViewContentSize: CGSize {
        size
    }

    override public func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        attributes.values.filter { $0.frame.intersects(rect) }
    }

    override public func layoutAttributesForItem(at indexPath: IndexPath)
        -> UICollectionViewLayoutAttributes? {
        attributes[indexPath]
    }

    override public func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.width != collectionView?.bounds.width
    }
}

@MainActor public final class WaterfallSectionLayout {
    private let make: (LayoutAccess<WaterfallSectionLayout>) -> any WaterfallDelegate
    private weak var access: LayoutAccess<WaterfallSectionLayout>?
    private var cachedDelegate: (any WaterfallDelegate)?

    public init(_ make: @escaping (LayoutAccess<WaterfallSectionLayout>) -> some WaterfallDelegate) {
        self.make = make
    }

    fileprivate func delegate(in access: LayoutAccess<WaterfallSectionLayout>) -> any WaterfallDelegate {
        if self.access === access, let cachedDelegate {
            return cachedDelegate
        }
        let delegate = make(access)
        self.access = access
        cachedDelegate = delegate
        return delegate
    }
}

/// A new layout family is assembled entirely in this external consumer module.
public extension CollectionLayout where Layout == WaterfallSectionLayout {
    static func waterfall() -> Self {
        Self(
            makeLayout: { _ in WaterfallLayout() },
            makeDelegate: { access in
                WaterfallBridge(access: access)
            }
        )
    }
}

private final class WaterfallBridge: CollectionLayoutDelegate, WaterfallDelegate {
    let access: LayoutAccess<WaterfallSectionLayout>
    init(access: LayoutAccess<WaterfallSectionLayout>) {
        self.access = access
        super.init()
    }

    func columns(in section: Int) -> Int {
        access.section(at: section)?.layoutValue.delegate(in: access).columns(in: section) ?? 1
    }

    func height(at path: IndexPath, width: CGFloat) -> CGFloat {
        access.section(at: path.section)?.layoutValue.delegate(in: access).height(at: path, width: width) ?? 0
    }
}

@MainActor public final class WaterfallCards: SectionController {
    public let id: String
    public let updateContext = SectionUpdateContext()
    public var cards: [Card]
    public var columns = 2
    public init(id: String = "waterfall", cards: [Card]) {
        self.id = id
        self.cards = cards
    }

    public func captureContent() -> LayoutContent<WaterfallSectionLayout> {
        let columns = columns
        return LayoutContent(cells: cards.map(AnyCellPresenter.init), layout: WaterfallSectionLayout { access in
            CardWaterfallDelegate(access: access, columns: columns)
        })
    }
}

private final class CardWaterfallDelegate: WaterfallDelegate {
    let access: LayoutAccess<WaterfallSectionLayout>
    let count: Int
    init(access: LayoutAccess<WaterfallSectionLayout>, columns: Int) {
        self.access = access
        count = columns
    }

    func columns(in _: Int) -> Int {
        count
    }

    func height(at path: IndexPath, width _: CGFloat) -> CGFloat {
        access.item(at: path, as: Card.self)?.height ?? 0
    }
}
