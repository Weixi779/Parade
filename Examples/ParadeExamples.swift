//
//  ParadeExamples.swift
//  ParadeExamples
//
//  Created by weixi on 2026/9/17.
//

import Parade
import UIKit

/// Add this file to an iOS app target and present either example controller.
/// Section owners supply captured native layouts and update their own presentation.
@MainActor
public final class IMExampleViewController: UIViewController {
    private lazy var sections = MessageDay.samples.map { day in
        MessageDayPresenter(day: day) { [weak self] error in
            self?.navigationItem.prompt = String(describing: error)
        }
    }

    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: UICollectionViewLayout()
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
        Task {
            do { try await orchestrator.setSections(sections, animated: false) }
            catch { navigationItem.prompt = String(describing: error) }
        }
    }

    private func receiveMessage() {
        let nextId = (sections.flatMap { $0.day.messages }.map(\.id).max() ?? 0) + 1
        let message = Message(
            id: nextId,
            content: .text("New message \(nextId)"),
            delivery: "Delivered"
        )
        Task {
            do { try await sections.last?.receive(message) }
            catch { navigationItem.prompt = String(describing: error) }
        }
    }
}

@MainActor
public final class AppStoreExampleViewController: UIViewController {
    private var page = StorePage.samples

    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: UICollectionViewLayout()
    )
    // This example injects Apple's implementation; the IM example uses Parade's default.
    private lazy var orchestrator = CollectionOrchestrator(collectionView: collectionView) {
        view, cell, supplementary in
        DiffableCollectionDataSource(
            collectionView: view,
            cellProvider: cell,
            supplementaryProvider: supplementary
        )
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "Discover"
        installCollectionView(collectionView, in: view)
        Task {
            do { try await orchestrator.setSections(sections, animated: false) }
            catch { navigationItem.prompt = String(describing: error) }
        }
    }

    private lazy var sections: [any StoreSectionPresenter] = {
        let install: @MainActor (String) -> Void = { [weak self] in self?.installOrOpen($0) }
        let open: @MainActor (String) -> Void = { [weak self] in
            self?.navigationItem.prompt = "Selected \($0)"
        }

        // Each section keeps a concrete, homogeneous model collection internally.
        // Type erasure occurs only when the presenters enter Parade's composition.
        return [
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
    }()

    private func installOrOpen(_ appId: String) {
        if page.installedIds.contains(appId) {
            navigationItem.prompt = "Opening \(appId)"
        } else {
            page.installedIds.insert(appId)
            for section in sections { section.installedIds = page.installedIds }
            Task {
                do { try await orchestrator.update(sections) }
                catch { navigationItem.prompt = String(describing: error) }
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

@MainActor
private final class MessageDayPresenter: SectionPresenter {
    let updates = SectionUpdateContext()
    private(set) var day: MessageDay
    private var expandedMessageIds: Set<Int> = []
    private let onError: @MainActor (any Error) -> Void

    init(day: MessageDay, onError: @escaping @MainActor (any Error) -> Void) {
        self.day = day
        self.onError = onError
    }

    func receive(_ message: Message) async throws {
        day.messages.append(message)
        try await update()
    }

    private func toggleExpansion(_ id: Int) {
        if expandedMessageIds.contains(id) { expandedMessageIds.remove(id) }
        else { expandedMessageIds.insert(id) }
        Task {
            do { try await update() }
            catch { onError(error) }
        }
    }

    func captureContent() -> DefaultSectionContent {
        DefaultSectionContent(cells: cells, supplementaryViews: supplementaryViews) { _ in
            makeVerticalSection(estimatedHeight: 96, hasHeader: true)
        }
    }

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
                    toggle: { [weak self] in self?.toggleExpansion(message.id) }
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

@MainActor
private protocol StoreSectionPresenter: SectionPresenter {
    var installedIds: Set<String> { get set }
}

@MainActor
private final class FeaturedSectionPresenter: StoreSectionPresenter {
    let updates = SectionUpdateContext()
    let model: FeaturedSectionModel
    var installedIds: Set<String>
    let install: @MainActor (String) -> Void
    let open: @MainActor (String) -> Void

    init(
        model: FeaturedSectionModel, installedIds: Set<String>,
        install: @escaping @MainActor (String) -> Void,
        open: @escaping @MainActor (String) -> Void
    ) {
        self.model = model
        self.installedIds = installedIds
        self.install = install
        self.open = open
    }

    func captureContent() -> DefaultSectionContent {
        DefaultSectionContent(cells: cells, supplementaryViews: supplementaryViews) { _ in
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
        }
    }

    var id: StoreSectionId { .featured }
    var cells: [AnyCellPresenter] {
        model.stories.map { story in
            AnyCellPresenter(FeaturedCellPresenter(
                story: story,
                installed: installedIds.contains(story.app.id),
                install: { [install] in install(story.app.id) },
                open: { [open] in open(story.app.id) }
            ))
        }
    }

    var supplementaryViews: [AnySupplementaryPresenter] {
        [AnySupplementaryPresenter(ExampleHeaderPresenter(id: id.rawValue, title: "Featured"))]
    }
}

@MainActor
private final class RankingSectionPresenter: StoreSectionPresenter {
    let updates = SectionUpdateContext()
    let model: RankingSectionModel
    var installedIds: Set<String>
    let install: @MainActor (String) -> Void
    let open: @MainActor (String) -> Void

    init(
        model: RankingSectionModel, installedIds: Set<String>,
        install: @escaping @MainActor (String) -> Void,
        open: @escaping @MainActor (String) -> Void
    ) {
        self.model = model
        self.installedIds = installedIds
        self.install = install
        self.open = open
    }

    func captureContent() -> DefaultSectionContent {
        DefaultSectionContent(cells: cells, supplementaryViews: supplementaryViews) { _ in
            return makeVerticalSection(estimatedHeight: 92, hasHeader: true)
        }
    }

    var id: StoreSectionId { .ranking }
    var cells: [AnyCellPresenter] {
        model.apps.enumerated().map { offset, app in
            AnyCellPresenter(RankingCellPresenter(
                app: app,
                rank: offset + 1,
                installed: installedIds.contains(app.app.id),
                install: { [install] in install(app.app.id) },
                open: { [open] in open(app.app.id) }
            ))
        }
    }

    var supplementaryViews: [AnySupplementaryPresenter] {
        [AnySupplementaryPresenter(ExampleHeaderPresenter(id: id.rawValue, title: "Top apps"))]
    }
}

@MainActor
private final class RecommendationSectionPresenter: StoreSectionPresenter {
    let updates = SectionUpdateContext()
    let model: RecommendationSectionModel
    var installedIds: Set<String>
    let install: @MainActor (String) -> Void
    let open: @MainActor (String) -> Void

    init(
        model: RecommendationSectionModel, installedIds: Set<String>,
        install: @escaping @MainActor (String) -> Void,
        open: @escaping @MainActor (String) -> Void
    ) {
        self.model = model
        self.installedIds = installedIds
        self.install = install
        self.open = open
    }

    func captureContent() -> DefaultSectionContent {
        DefaultSectionContent(cells: cells, supplementaryViews: supplementaryViews) { _ in
            return makeVerticalSection(estimatedHeight: 130, hasHeader: true)
        }
    }

    var id: StoreSectionId { .recommendations }
    var cells: [AnyCellPresenter] {
        model.apps.map { app in
            AnyCellPresenter(RecommendationCellPresenter(
                app: app,
                installed: installedIds.contains(app.app.id),
                install: { [install] in install(app.app.id) },
                open: { [open] in open(app.app.id) }
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
