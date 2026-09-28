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
    public override func prepare() {
        super.prepare()
        guard let view = collectionView, let delegate = view.delegate as? WaterfallDelegate else { return }
        attributes.removeAll()
        var y: CGFloat = 12
        for section in 0..<view.numberOfSections {
            let columns = max(1, delegate.columns(in: section))
            let width = floor((view.bounds.width - 32 - CGFloat(columns - 1) * 10) / CGFloat(columns))
            var bottoms = Array(repeating: y, count: columns)
            for item in 0..<view.numberOfItems(inSection: section) {
                let column = bottoms.indices.min { bottoms[$0] < bottoms[$1] }!
                let path = IndexPath(item: item, section: section)
                let attribute = UICollectionViewLayoutAttributes(forCellWith: path)
                attribute.frame = CGRect(x: 16 + CGFloat(column) * (width + 10), y: bottoms[column], width: width,
                    height: delegate.height(at: path, width: width))
                attributes[path] = attribute
                bottoms[column] = attribute.frame.maxY + 10
            }
            y = (bottoms.max() ?? y) + 12
        }
        size = CGSize(width: view.bounds.width, height: y)
    }
    public override var collectionViewContentSize: CGSize { size }
    public override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        attributes.values.filter { $0.frame.intersects(rect) }
    }
    public override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? { attributes[indexPath] }
    public override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.width != collectionView?.bounds.width
    }
}

@MainActor public final class WaterfallSectionLayout {
    let make: (LayoutAccess<WaterfallSectionLayout>) -> Queries
    struct Queries {
        let columns: (Int) -> Int
        let height: (IndexPath, CGFloat) -> CGFloat
    }
    public init<D: WaterfallDelegate>(_ make: @escaping (LayoutAccess<WaterfallSectionLayout>) -> D) {
        self.make = { access in
            let delegate = make(access)
            return Queries(columns: delegate.columns, height: delegate.height)
        }
    }
}

/// A new layout family is assembled entirely in this external consumer module.
public extension CollectionLayout where Layout == WaterfallSectionLayout {
    static func waterfall() -> Self {
        Self(makeLayout: { _ in WaterfallLayout() }, makeDelegate: { view, access in
            WaterfallBridge(collectionView: view, access: access)
        })
    }
}

private final class WaterfallBridge: CollectionViewBridge<WaterfallSectionLayout>, WaterfallDelegate {
    let access: LayoutAccess<WaterfallSectionLayout>
    init(collectionView: UICollectionView, access: LayoutAccess<WaterfallSectionLayout>) {
        self.access = access
        super.init(collectionView: collectionView)
    }
    func columns(in section: Int) -> Int {
        access.section(at: section)?.layoutValue.make(access).columns(section) ?? 1
    }
    func height(at path: IndexPath, width: CGFloat) -> CGFloat {
        access.section(at: path.section)?.layoutValue.make(access).height(path, width) ?? 0
    }
}

@MainActor public final class WaterfallCards: SectionController {
    public let id: String
    public let updateContext = SectionUpdateContext()
    public var cards: [Card]
    public var columns = 2
    public init(id: String = "waterfall", cards: [Card]) { self.id = id; self.cards = cards }
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
    init(access: LayoutAccess<WaterfallSectionLayout>, columns: Int) { self.access = access; count = columns }
    func columns(in section: Int) -> Int { count }
    func height(at path: IndexPath, width: CGFloat) -> CGFloat {
        access.item(at: path, as: Card.self)?.height ?? 0
    }
}
