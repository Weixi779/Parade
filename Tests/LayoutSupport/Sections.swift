// Created by weixi on 2026/10/02.

import Parade
import UIKit

@MainActor public final class EventLog {
    public var selected: [Int] = []
    public var displayed: [Int] = []
    public var sizes: [(id: Int, height: CGFloat)] = []
    public weak var lastDelegate: NSObject?
    public weak var lastAccess: LayoutAccess<FlowSectionLayout>?
    public var factories = 0
    public init() {}
}

public final class CardCell: UICollectionViewCell {
    public let label = UILabel()
    override public init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 14
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .white
        contentView.addSubview(label)
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds.insetBy(dx: 14, dy: 12)
    }
}

public struct Card: CellPresenter, CellSelectionHandling, CellDisplayObserving {
    public let id: Int
    public var height: CGFloat
    public let log: EventLog
    public init(_ id: Int, height: CGFloat, log: EventLog) {
        self.id = id
        self.height = height
        self.log = log
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && a.height == b.height
    }

    public func configure(_ cell: CardCell) {
        cell.label.text = "Card \(id)\n\(Int(height)) pt"
        cell.contentView.backgroundColor = [.systemIndigo, .systemTeal, .systemOrange, .systemPurple][abs(id) % 4]
    }

    public func didSelect(_: CardCell) {
        log.selected.append(id)
    }

    public func willDisplay(_: CardCell) {
        log.displayed.append(id)
    }
}

public final class HeaderView: UICollectionReusableView {
    let label = UILabel()
    override public init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.textColor = .secondaryLabel
        addSubview(label)
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 16, dy: 0)
    }
}

public struct Header: SupplementaryPresenter {
    public let id: String
    public var elementKind: String {
        Self.headerKind
    }

    public func configure(_ view: HeaderView) {
        view.label.text = id
    }
}

@MainActor public final class FlowCards: SectionController {
    public let id: String
    public let updateContext = SectionUpdateContext()
    public var cards: [Card]
    public var scale: CGFloat = 1
    public var columns = 2
    public let log: EventLog
    public init(id: String = "cards", cards: [Card], log: EventLog) {
        self.id = id
        self.cards = cards
        self.log = log
    }

    public func captureContent() -> LayoutContent<FlowSectionLayout> {
        let scale = scale, columns = columns, log = log
        return LayoutContent(
            cells: cards.map(AnyCellPresenter.init),
            supplementaryViews: [AnySupplementaryPresenter(Header(id: id))],
            layout: FlowSectionLayout { access in
                log.factories += 1
                log.lastAccess = access
                let delegate = CardFlowDelegate(
                    access: access,
                    columns: columns,
                    scale: scale,
                    log: log
                )
                log.lastDelegate = delegate
                return delegate
            }
        )
    }
}

/// A second section type and a second concrete native delegate in the same collection.
@MainActor public final class FlowBanner: SectionController {
    public let id = "banner"
    public let updateContext = SectionUpdateContext()
    public let card: Card
    public init(log: EventLog) {
        card = Card(900, height: 64, log: log)
    }

    public func captureContent() -> LayoutContent<FlowSectionLayout> {
        LayoutContent(cells: [AnyCellPresenter(card)], layout: FlowSectionLayout { _ in BannerFlowDelegate() })
    }
}

private final class BannerFlowDelegate: NSObject, UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ view: UICollectionView,
        layout _: UICollectionViewLayout,
        sizeForItemAt _: IndexPath
    ) -> CGSize {
        CGSize(width: view.bounds.width - 32, height: 64)
    }

    func collectionView(
        _: UICollectionView,
        layout _: UICollectionViewLayout,
        insetForSectionAt _: Int
    ) -> UIEdgeInsets {
        UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
    }
}

private final class CardFlowDelegate: NSObject, UICollectionViewDelegateFlowLayout {
    let access: LayoutAccess<FlowSectionLayout>
    let columns: Int
    let scale: CGFloat
    let log: EventLog
    init(access: LayoutAccess<FlowSectionLayout>, columns: Int, scale: CGFloat, log: EventLog) {
        self.access = access
        self.columns = columns
        self.scale = scale
        self.log = log
    }

    func collectionView(
        _ view: UICollectionView,
        layout _: UICollectionViewLayout,
        sizeForItemAt path: IndexPath
    ) -> CGSize {
        guard let item = access.item(at: path, as: Card.self) else {
            return .zero
        }
        let height = item.height * scale
        log.sizes.append((item.id, height))
        return CGSize(
            width: floor((view.bounds.width - 32 - CGFloat(columns - 1) * 10) / CGFloat(columns)),
            height: height
        )
    }

    func collectionView(
        _: UICollectionView,
        layout _: UICollectionViewLayout,
        insetForSectionAt _: Int
    ) -> UIEdgeInsets {
        UIEdgeInsets(top: 8, left: 16, bottom: 16, right: 16)
    }

    func collectionView(
        _ view: UICollectionView,
        layout _: UICollectionViewLayout,
        referenceSizeForHeaderInSection _: Int
    ) -> CGSize {
        CGSize(width: view.bounds.width, height: 32)
    }
}

@MainActor public final class CompositionalCards: SectionController {
    public let id = "compositional"
    public let updateContext = SectionUpdateContext()
    public var cards: [Card]
    public var height: CGFloat = 92
    public init(cards: [Card]) {
        self.cards = cards
    }

    public func captureContent() -> LayoutContent<CompositionalSectionLayout> {
        let height = height
        return LayoutContent(cells: cards.map(AnyCellPresenter.init), layout: CompositionalSectionLayout { _ in
            let item = NSCollectionLayoutItem(layoutSize: .init(
                widthDimension: .fractionalWidth(1),
                heightDimension: .fractionalHeight(1)
            ))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height)),
                subitems: [item]
            )
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 10
            section.contentInsets = .init(top: 12, leading: 16, bottom: 16, trailing: 16)
            return section
        })
    }
}

@MainActor public final class Fixture<Layout> {
    public let view: UICollectionView
    public let owner: CollectionOrchestrator<Layout>
    public let host = UIViewController()
    public let window: UIWindow
    public init(layout: CollectionLayout<Layout>, diffable: Bool = false) {
        view = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 720),
            collectionViewLayout: UICollectionViewFlowLayout()
        )
        if diffable {
            owner = CollectionOrchestrator(collectionView: view, layout: layout) { view, cell, supplementary in
                DiffableCollectionDataSource(
                    collectionView: view,
                    cellProvider: cell,
                    supplementaryProvider: supplementary
                )
            }
        } else {
            owner = CollectionOrchestrator(collectionView: view, layout: layout)
        }
        window = UIWindow(frame: view.frame)
        host.view = view
        window.rootViewController = host
        window.makeKeyAndVisible()
        owner.isVisible = true
    }

    public func settle() {
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    public func frame(_ id: Int) -> CGRect? {
        guard let path = owner.indexPath(for: id) else {
            return nil
        }
        return view.collectionViewLayout.layoutAttributesForItem(at: path)?.frame
    }
}
