//
//  ParadeExamples.swift
//  ParadeExamples
//
//  Created by weixi on 2026/9/17.
//

import Parade
import UIKit

/// Add this file to an iOS app target and present either example controller.
/// The application creates the collection view, layout, and business state.
@MainActor
public final class IMExampleViewController: UIViewController {
    private var days = MessageDay.samples
    private var expandedMessageIds: Set<Int> = []

    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: makeLayout()
    )
    private lazy var orchestrator = CollectionOrchestrator(collectionView: collectionView)

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "Conversation"
        installCollectionView(collectionView, in: view)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Receive",
            primaryAction: UIAction { [weak self] _ in self?.receiveMessage() }
        )
        render(animated: false)
    }

    private func render(animated: Bool = true) {
        let sections: [any SectionPresenter] = days.map { day in
            MessageDayPresenter(
                day: day,
                expandedMessageIds: expandedMessageIds
            ) { [weak self] id in
                self?.toggleExpansion(id)
            }
        }
        orchestrator.apply(sections, animated: animated) { [weak self] result in
            if case .failure(let error) = result {
                self?.navigationItem.prompt = String(describing: error)
            }
        }
    }

    private func toggleExpansion(_ id: Int) {
        if expandedMessageIds.contains(id) {
            expandedMessageIds.remove(id)
        } else {
            expandedMessageIds.insert(id)
        }
        render()
    }

    private func receiveMessage() {
        let nextId = (days.flatMap(\.messages).map(\.id).max() ?? 0) + 1
        days[days.count - 1].messages.append(Message(
            id: nextId,
            content: .text("New message \(nextId)"),
            delivery: "Delivered"
        ))
        render()
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, _ in
            guard let self, self.orchestrator.sectionId(at: index)?.base is String else {
                return nil
            }
            return makeVerticalSection(estimatedHeight: 96, hasHeader: true)
        }
    }
}

@MainActor
public final class AppStoreExampleViewController: UIViewController {
    private var page = StorePage.samples

    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: makeLayout()
    )
    private lazy var orchestrator = CollectionOrchestrator(collectionView: collectionView)

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "Discover"
        installCollectionView(collectionView, in: view)
        render(animated: false)
    }

    private func render(animated: Bool = true) {
        let install: @MainActor (String) -> Void = { [weak self] in self?.installOrOpen($0) }
        let open: @MainActor (String) -> Void = { [weak self] in
            self?.navigationItem.prompt = "Selected \($0)"
        }

        // Each section keeps a concrete, homogeneous model collection internally.
        // Type erasure occurs only when the presenters enter Parade's composition.
        let sections: [any SectionPresenter] = [
            FeaturedSectionPresenter(
                model: page.featured,
                installedIds: page.installedIds,
                install: install,
                open: open
            ),
            RankingSectionPresenter(
                model: page.ranking,
                installedIds: page.installedIds,
                install: install,
                open: open
            ),
            RecommendationSectionPresenter(
                model: page.recommendations,
                installedIds: page.installedIds,
                install: install,
                open: open
            ),
        ]
        orchestrator.apply(sections, animated: animated) { [weak self] result in
            if case .failure(let error) = result {
                self?.navigationItem.prompt = String(describing: error)
            }
        }
    }

    private func installOrOpen(_ appId: String) {
        if page.installedIds.contains(appId) {
            navigationItem.prompt = "Opening \(appId)"
        } else {
            page.installedIds.insert(appId)
            // One application-owned state change refreshes every occurrence.
            render()
        }
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, _ in
            guard let self,
                  let id = self.orchestrator.sectionId(at: index)?.base as? StoreSectionId else {
                return nil
            }
            switch id {
            case .featured:
                let item = NSCollectionLayoutItem(layoutSize: .init(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .fractionalHeight(1)
                ))
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: .init(
                        widthDimension: .fractionalWidth(0.86),
                        heightDimension: .absolute(210)
                    ),
                    subitems: [item]
                )
                let section = NSCollectionLayoutSection(group: group)
                section.orthogonalScrollingBehavior = .groupPaging
                section.interGroupSpacing = 12
                section.contentInsets = .init(top: 8, leading: 16, bottom: 24, trailing: 16)
                section.boundarySupplementaryItems = [makeHeader()]
                return section
            case .ranking:
                return makeVerticalSection(estimatedHeight: 92, hasHeader: true)
            case .recommendations:
                return makeVerticalSection(estimatedHeight: 130, hasHeader: true)
            }
        }
    }
}

// MARK: - Application models

private struct Message: Equatable {
    enum Content: Equatable {
        case text(String)
        case attachment(title: String, symbol: String)
    }

    let id: Int
    var content: Content
    var delivery: String
}

private struct MessageDay {
    let id: String
    var messages: [Message]

    static let samples = [
        MessageDay(id: "Yesterday", messages: [
            Message(
                id: 1,
                content: .text("Have you tried the new collection framework?"),
                delivery: "Read"
            ),
            Message(
                id: 2,
                content: .attachment(title: "Architecture sketch", symbol: "photo"),
                delivery: "Read"
            ),
        ]),
        MessageDay(id: "Today", messages: [
            Message(
                id: 3,
                content: .text(
                    "One message becomes one typed cell presenter.\nA day remains a real section.\nThe application owns expansion state.\nTap Expand to reveal the rest.\nContent comparison includes that state, and the system layout handles the changed height."
                ),
                delivery: "Delivered"
            ),
            Message(
                id: 4,
                content: .attachment(title: "Voice message · 0:14", symbol: "waveform"),
                delivery: "Delivered"
            ),
            Message(id: 5, content: .text("Let's build the homepage next."), delivery: "Sent"),
        ]),
    ]
}

private enum StoreSectionId: String, Hashable { case featured, ranking, recommendations }

private struct StoreApp: Equatable {
    let id: String
    let name: String
    let category: String
}

private struct FeaturedStory: Equatable {
    let app: StoreApp
    let headline: String
}

private struct RankedApp: Equatable {
    let app: StoreApp
    let rating: String
}

private struct RecommendedApp: Equatable {
    let app: StoreApp
    let reason: String
}

private struct FeaturedSectionModel { let stories: [FeaturedStory] }
private struct RankingSectionModel { let apps: [RankedApp] }
private struct RecommendationSectionModel { let apps: [RecommendedApp] }

private struct StorePage {
    let featured: FeaturedSectionModel
    let ranking: RankingSectionModel
    let recommendations: RecommendationSectionModel
    var installedIds: Set<String> = []

    static let samples: StorePage = {
        let iris = StoreApp(id: "iris", name: "Iris", category: "Photography")
        let parade = StoreApp(id: "parade", name: "Parade", category: "Developer tools")
        let audio = StoreApp(id: "audio", name: "AudioHelm", category: "Music")
        let ravel = StoreApp(id: "ravel", name: "Ravel", category: "Productivity")
        return StorePage(
            featured: FeaturedSectionModel(stories: [
                FeaturedStory(app: iris, headline: "A different way to see"),
                FeaturedStory(app: parade, headline: "Your next collection"),
            ]),
            ranking: RankingSectionModel(apps: [
                RankedApp(app: iris, rating: "4.9"),
                RankedApp(app: audio, rating: "4.8"),
                RankedApp(app: parade, rating: "4.8"),
                RankedApp(app: ravel, rating: "4.7"),
            ]),
            recommendations: RecommendationSectionModel(apps: [
                RecommendedApp(app: audio, reason: "Make room for a little music"),
                RecommendedApp(app: iris, reason: "Keep the everyday moments"),
                RecommendedApp(app: ravel, reason: "Bring your work together"),
            ])
        )
    }()
}

/// The same app has distinct cell identities in different sections.
private struct StoreOccurrenceId: Hashable {
    let section: StoreSectionId
    let appId: String
}

// MARK: - Sections

private struct MessageDayPresenter: SectionPresenter {
    let day: MessageDay
    let expandedMessageIds: Set<Int>
    let toggleExpansion: @MainActor (Int) -> Void

    var id: String { day.id }
    var cells: [AnyCellPresenter] {
        day.messages.map { message in
            switch message.content {
            case .text(let text):
                return AnyCellPresenter(TextMessagePresenter(
                    id: message.id,
                    text: text,
                    delivery: message.delivery,
                    expanded: expandedMessageIds.contains(message.id),
                    toggle: { toggleExpansion(message.id) }
                ))
            case let .attachment(title, symbol):
                return AnyCellPresenter(AttachmentMessagePresenter(
                    id: message.id,
                    title: title,
                    symbol: symbol,
                    delivery: message.delivery
                ))
            }
        }
    }

    var supplementaryViews: [AnySupplementaryPresenter] {
        [AnySupplementaryPresenter(ExampleHeaderPresenter(id: day.id, title: day.id))]
    }
}

private struct FeaturedSectionPresenter: SectionPresenter {
    let model: FeaturedSectionModel
    let installedIds: Set<String>
    let install: @MainActor (String) -> Void
    let open: @MainActor (String) -> Void

    var id: StoreSectionId { .featured }
    var cells: [AnyCellPresenter] {
        model.stories.map { story in
            AnyCellPresenter(FeaturedCellPresenter(
                story: story,
                installed: installedIds.contains(story.app.id),
                install: { install(story.app.id) },
                open: { open(story.app.id) }
            ))
        }
    }

    var supplementaryViews: [AnySupplementaryPresenter] {
        [AnySupplementaryPresenter(ExampleHeaderPresenter(id: id.rawValue, title: "Featured"))]
    }
}

private struct RankingSectionPresenter: SectionPresenter {
    let model: RankingSectionModel
    let installedIds: Set<String>
    let install: @MainActor (String) -> Void
    let open: @MainActor (String) -> Void

    var id: StoreSectionId { .ranking }
    var cells: [AnyCellPresenter] {
        model.apps.enumerated().map { offset, app in
            AnyCellPresenter(RankingCellPresenter(
                app: app,
                rank: offset + 1,
                installed: installedIds.contains(app.app.id),
                install: { install(app.app.id) },
                open: { open(app.app.id) }
            ))
        }
    }

    var supplementaryViews: [AnySupplementaryPresenter] {
        [AnySupplementaryPresenter(ExampleHeaderPresenter(id: id.rawValue, title: "Top apps"))]
    }
}

private struct RecommendationSectionPresenter: SectionPresenter {
    let model: RecommendationSectionModel
    let installedIds: Set<String>
    let install: @MainActor (String) -> Void
    let open: @MainActor (String) -> Void

    var id: StoreSectionId { .recommendations }
    var cells: [AnyCellPresenter] {
        model.apps.map { app in
            AnyCellPresenter(RecommendationCellPresenter(
                app: app,
                installed: installedIds.contains(app.app.id),
                install: { install(app.app.id) },
                open: { open(app.app.id) }
            ))
        }
    }

    var supplementaryViews: [AnySupplementaryPresenter] {
        [AnySupplementaryPresenter(ExampleHeaderPresenter(id: id.rawValue, title: "For you"))]
    }
}

// MARK: - Cells and supplementary presentation

private struct TextMessagePresenter: CellPresenter, CellSelectionHandling {
    let id: Int
    let text: String
    let delivery: String
    let expanded: Bool
    let toggle: @MainActor () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.delivery == rhs.delivery && lhs.expanded == rhs.expanded
    }

    func configure(_ cell: TextMessageCell) {
        cell.titleLabel.text = text
        cell.titleLabel.numberOfLines = expanded ? 0 : 3
        cell.detailLabel.text = delivery
        cell.actionButton.setTitle(expanded ? "Collapse" : "Expand", for: .normal)
    }

    func setBehaviors(_ cell: TextMessageCell) { cell.onAction = toggle }
    func didSelect(_ cell: TextMessageCell) { toggle() }
}

private struct AttachmentMessagePresenter: CellPresenter {
    let id: Int
    let title: String
    let symbol: String
    let delivery: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title && lhs.symbol == rhs.symbol && lhs.delivery == rhs.delivery
    }

    func configure(_ cell: AttachmentMessageCell) {
        cell.titleLabel.text = title
        cell.detailLabel.text = delivery
        cell.actionButton.setImage(UIImage(systemName: symbol), for: .normal)
        cell.actionButton.isUserInteractionEnabled = false
    }
}

private struct FeaturedCellPresenter: CellPresenter, CellSelectionHandling {
    let story: FeaturedStory
    let installed: Bool
    let install: @MainActor () -> Void
    let open: @MainActor () -> Void

    var id: StoreOccurrenceId { .init(section: .featured, appId: story.app.id) }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.story == rhs.story && lhs.installed == rhs.installed
    }

    func configure(_ cell: FeaturedCardCell) {
        cell.titleLabel.text = story.headline
        cell.titleLabel.font = .preferredFont(forTextStyle: .title2)
        cell.detailLabel.text = story.app.name
        cell.actionButton.setTitle(installed ? "Open" : "Get", for: .normal)
        cell.contentView.backgroundColor = .secondarySystemGroupedBackground
    }

    func setBehaviors(_ cell: FeaturedCardCell) { cell.onAction = install }
    func didSelect(_ cell: FeaturedCardCell) { open() }
}

private struct RankingCellPresenter: CellPresenter, CellSelectionHandling {
    let app: RankedApp
    let rank: Int
    let installed: Bool
    let install: @MainActor () -> Void
    let open: @MainActor () -> Void

    var id: StoreOccurrenceId { .init(section: .ranking, appId: app.app.id) }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.app == rhs.app && lhs.rank == rhs.rank && lhs.installed == rhs.installed
    }

    func configure(_ cell: RankingCell) {
        cell.titleLabel.text = "\(rank). \(app.app.name)"
        cell.detailLabel.text = "\(app.app.category) · ★ \(app.rating)"
        cell.actionButton.setTitle(installed ? "Open" : "Get", for: .normal)
    }

    func setBehaviors(_ cell: RankingCell) { cell.onAction = install }
    func didSelect(_ cell: RankingCell) { open() }
}

private struct RecommendationCellPresenter: CellPresenter, CellSelectionHandling {
    let app: RecommendedApp
    let installed: Bool
    let install: @MainActor () -> Void
    let open: @MainActor () -> Void

    var id: StoreOccurrenceId { .init(section: .recommendations, appId: app.app.id) }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.app == rhs.app && lhs.installed == rhs.installed
    }

    func configure(_ cell: RecommendationCell) {
        cell.titleLabel.text = app.app.name
        cell.detailLabel.text = app.reason
        cell.actionButton.setTitle(installed ? "Open" : "Get", for: .normal)
    }

    func setBehaviors(_ cell: RecommendationCell) { cell.onAction = install }
    func didSelect(_ cell: RecommendationCell) { open() }
}

private struct ExampleHeaderPresenter: SupplementaryPresenter {
    let id: String
    let title: String
    var elementKind: String { Self.headerKind }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }
    func configure(_ view: ExampleHeaderView) { view.titleLabel.text = title }
}

// MARK: - Ordinary application-owned UIKit views and layout

@MainActor
private class ExampleActionCell: UICollectionViewCell {
    let titleLabel = UILabel()
    let detailLabel = UILabel()
    let actionButton = UIButton(type: .system)
    var onAction: (@MainActor () -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0
        detailLabel.adjustsFontForContentSizeCategory = true
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        let labels = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        labels.axis = .vertical
        labels.spacing = 6
        let row = UIStackView(arrangedSubviews: [labels, actionButton])
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        contentView.layer.cornerRadius = 14
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
        ])
        // Install the UIKit action once. setBehaviors replaces only onAction.
        actionButton.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func prepareForReuse() {
        super.prepareForReuse()
        onAction = nil
    }
}

@MainActor private final class TextMessageCell: ExampleActionCell {}
@MainActor private final class AttachmentMessageCell: ExampleActionCell {}
@MainActor private final class FeaturedCardCell: ExampleActionCell {}
@MainActor private final class RankingCell: ExampleActionCell {}
@MainActor private final class RecommendationCell: ExampleActionCell {}

@MainActor
private final class ExampleHeaderView: UICollectionReusableView {
    let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
}

@MainActor
private func installCollectionView(_ collectionView: UICollectionView, in container: UIView) {
    container.backgroundColor = .systemBackground
    collectionView.backgroundColor = .systemBackground
    collectionView.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(collectionView)
    NSLayoutConstraint.activate([
        collectionView.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
        collectionView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        collectionView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        collectionView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    ])
}

@MainActor
private func makeVerticalSection(
    estimatedHeight: CGFloat,
    hasHeader: Bool
) -> NSCollectionLayoutSection {
    let item = NSCollectionLayoutItem(layoutSize: .init(
        widthDimension: .fractionalWidth(1),
        heightDimension: .estimated(estimatedHeight)
    ))
    let group = NSCollectionLayoutGroup.vertical(
        layoutSize: .init(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(estimatedHeight)
        ),
        subitems: [item]
    )
    let section = NSCollectionLayoutSection(group: group)
    section.interGroupSpacing = 8
    section.contentInsets = .init(top: 8, leading: 16, bottom: 24, trailing: 16)
    if hasHeader { section.boundarySupplementaryItems = [makeHeader()] }
    return section
}

@MainActor
private func makeHeader() -> NSCollectionLayoutBoundarySupplementaryItem {
    NSCollectionLayoutBoundarySupplementaryItem(
        layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(48)),
        elementKind: UICollectionView.elementKindSectionHeader,
        alignment: .top
    )
}
