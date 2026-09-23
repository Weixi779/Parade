// Created by weixi on 2026/09/17.

import Testing
import UIKit
@testable import Parade

@MainActor
struct CollectionViewBridgeTests {
    @Test("Forwarding preserves return values and mutable scroll destinations")
    func delegateForwarding() throws {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 23
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        let owner = CollectionOrchestrator(collectionView: view)
        let bridge = try #require(view.delegate as? CollectionViewBridge)
        let delegate = ForwardingDelegate()
        owner.scrollViewDelegate = delegate

        bridge.scrollViewDidScroll(view)
        var destination = CGPoint.zero
        bridge.scrollViewWillEndDragging(
            view,
            withVelocity: CGPoint(x: 2, y: 3),
            targetContentOffset: &destination
        )

        #expect(delegate.scrollCount == 1)
        #expect(delegate.velocity == CGPoint(x: 2, y: 3))
        #expect(destination == CGPoint(x: 7, y: 11))
        #expect(!bridge.scrollViewShouldScrollToTop(view))

    }

    @Test("A removed cell's final callback belongs to its actual presenter, not its old index path")
    func removedCellKeepsDisplayBinding() async throws {
        let fixture = Fixture()
        defer { fixture.window.isHidden = true }
        let events = Events()
        try await fixture.owner.setSections(
            [Section(id: "section", cells: [cell("old", token: "old", events: events)])],
            animated: false
        )
        let cell = try #require(fixture.view.cellForItem(at: .init(item: 0, section: 0)))
        let bridge = try #require(fixture.view.delegate as? CollectionViewBridge)
        #expect(events.started == ["old"])

        // This is the instant between installing new data-source counts and
        // UIKit delivering the disappearing old cell's end-display callback.
        fixture.installDisplayVersion([SectionSnapshot(
            id: "section",
            cells: [self.cell("new", token: "new", events: events)]
        )])
        bridge.collectionView(
            fixture.view,
            didEndDisplaying: cell,
            forItemAt: .init(item: 0, section: 0)
        )

        #expect(events.ended == ["old"])
    }

    @Test("Equal visual content still replaces cell actions and selection callbacks")
    func behaviorOnlySubmissionRefreshesVisibleBindings() async throws {
        let fixture = Fixture()
        defer { fixture.window.isHidden = true }
        let events = Events()
        let globalEvents = GlobalEvents()
        fixture.owner.eventHandler = globalEvents
        try await fixture.owner.setSections(
            [Section(id: "section", cells: [cell("same", token: "first", events: events)])],
            animated: false
        )
        let initial = try #require(fixture.view.cellForItem(at: .init(
            item: 0,
            section: 0
        )) as? ActionCell)
        let configurations = events.configurationCount

        try await fixture.owner.setSections(
            [Section(id: "section", cells: [cell("same", token: "second", events: events)])],
            animated: false
        )
        let current = try #require(fixture.view.cellForItem(at: .init(
            item: 0,
            section: 0
        )) as? ActionCell)
        let bridge = try #require(fixture.view.delegate as? CollectionViewBridge)
        current.action?()
        bridge.collectionView(fixture.view, didSelectItemAt: .init(item: 0, section: 0))

        #expect(initial === current)
        #expect(events.configurationCount == configurations)
        #expect(events.actions == ["second"])
        #expect(events.selected == ["second"])
        #expect(globalEvents.selectedIds == [AnyHashable("same")])
        #expect(globalEvents.sectionIds == [AnyHashable("section")])
    }

    @Test(
        "Cell behavior refresh updates every active display and preserves unmatched-path recovery",
        arguments: [false, true]
    )
    func activeCellDisplaysUseLatestBehavior(matchingPath: Bool) async throws {
        let fixture = Fixture()
        defer { fixture.window.isHidden = true }
        let events = Events()
        let path = IndexPath(item: 0, section: 0)
        try await fixture.owner.setSections(
            [Section(id: "section", cells: [cell("same", token: "first", events: events)])],
            animated: false
        )
        let view = try #require(fixture.view.cellForItem(at: path) as? ActionCell)
        let bridge = try #require(fixture.view.delegate as? CollectionViewBridge)
        bridge.collectionView(fixture.view, willDisplay: view, forItemAt: path)
        #expect(events.started == ["first", "first"])
        let configurations = events.configurationCount

        fixture.installDisplayVersion([SectionSnapshot(
            id: "section",
            cells: [cell("same", token: "latest", events: events)]
        )])
        bridge.refreshVisibleBehaviors()
        view.action?()

        let endPath = matchingPath ? path : IndexPath(item: 9, section: 9)
        bridge.collectionView(fixture.view, didEndDisplaying: view, forItemAt: endPath)
        bridge.collectionView(fixture.view, didEndDisplaying: view, forItemAt: endPath)
        bridge.collectionView(fixture.view, didEndDisplaying: view, forItemAt: endPath)
        #expect(events.ended == ["latest", "latest"])
        #expect(events.actions == ["latest"])
        #expect(events.configurationCount == configurations)
    }

    @Test(
        "Selection capability can be removed and restored while retaining the cell and global events"
    )
    func selectionCapabilityChanges() async throws {
        let fixture = Fixture()
        defer { fixture.window.isHidden = true }
        let events = Events()
        let globalEvents = GlobalEvents()
        fixture.owner.eventHandler = globalEvents
        let path = IndexPath(item: 0, section: 0)
        let bridge = try #require(fixture.view.delegate as? CollectionViewBridge)

        try await fixture.owner.setSections(
            [Section(id: "section", cells: [cell("same", token: "first", events: events)])],
            animated: false
        )
        let original = try #require(fixture.view.cellForItem(at: path))
        bridge.collectionView(fixture.view, didSelectItemAt: path)

        try await fixture.owner.setSections(
            [Section(id: "section", cells: [AnyCellPresenter(StaticPresenter(id: "same"))])],
            animated: false
        )
        #expect(fixture.view.cellForItem(at: path) === original)
        let staticCell = try #require(fixture.view.cellForItem(at: path) as? ActionCell)
        #expect(staticCell.action == nil)
        #expect(bridge.collectionView(fixture.view, shouldSelectItemAt: path))
        bridge.collectionView(fixture.view, didSelectItemAt: path)
        #expect(events.selected == ["first"])
        #expect(globalEvents.selectedIds == [AnyHashable("same"), AnyHashable("same")])

        try await fixture.owner.setSections(
            [Section(id: "section", cells: [cell("same", token: "latest", events: events)])],
            animated: false
        )
        #expect(fixture.view.cellForItem(at: path) === original)
        bridge.collectionView(fixture.view, didSelectItemAt: path)
        #expect(events.selected == ["first", "latest"])
        #expect(globalEvents.selectedIds.count == 3)
    }

    @Test("Supplementary presenters sharing a view replace content and clear previous actions")
    func supplementaryPresenterReplacementClearsBindings() async throws {
        let fixture = Fixture(header: true)
        defer { fixture.window.isHidden = true }
        let events = Events()
        let kind = UICollectionView.elementKindSectionHeader
        let path = IndexPath(item: 0, section: 0)
        let first = AnySupplementaryPresenter(Header(
            id: "header",
            events: events,
            token: "first",
            content: "First"
        ))
        let section = Section(
            id: "section",
            cells: [cell("cell", token: "cell", events: events)],
            supplementaryViews: [first]
        )
        try await fixture.owner.setSections([section], animated: false)
        let original = try #require(fixture.view.supplementaryView(
            forElementKind: kind,
            at: path
        ) as? ActionHeader)
        original.action?()

        let replacement = AnySupplementaryPresenter(StaticHeader(id: "header"))
        #expect(first.registrationKey == replacement.registrationKey)
        #expect(first != replacement)
        section.supplementaryViews = [replacement]
        try await fixture.owner.update([section], animated: false)
        let retained = try #require(fixture.view.supplementaryView(
            forElementKind: kind,
            at: path
        ) as? ActionHeader)
        #expect(retained === original)
        #expect(retained.content == "Static")
        #expect(retained.action == nil)

        section.supplementaryViews = [AnySupplementaryPresenter(Header(
            id: "header",
            events: events,
            token: "latest",
            content: "Latest"
        ))]
        try await fixture.owner.update([section], animated: false)
        let current = try #require(fixture.view.supplementaryView(
            forElementKind: kind,
            at: path
        ) as? ActionHeader)
        #expect(current === original)
        #expect(current.content == "Latest")
        current.action?()
        #expect(events.actions == ["first", "latest"])
    }

    @Test(
        "Interaction consumers use the current policies and callbacks after an equal-content update"
    )
    func interactionCapabilitiesUseCurrentBinding() async throws {
        let fixture = Fixture()
        defer { fixture.window.isHidden = true }
        let events = InteractionEvents()
        let path = IndexPath(item: 0, section: 0)
        let bridge = try #require(fixture.view.delegate as? CollectionViewBridge)

        let first = AnyCellPresenter(InteractionPresenter(
            token: "first",
            allowed: false,
            events: events
        ))
        try await fixture.owner.setSections([Section(id: "section", cells: [first])], animated: false)
        let original = try #require(fixture.view.cellForItem(at: path))
        let initialConfigurations = events.configurations
        #expect(!bridge.collectionView(fixture.view, shouldSelectItemAt: path))
        #expect(!bridge.collectionView(fixture.view, shouldDeselectItemAt: path))
        #expect(!bridge.collectionView(fixture.view, shouldHighlightItemAt: path))

        let next = AnyCellPresenter(InteractionPresenter(
            token: "next",
            allowed: true,
            events: events
        ))
        #expect(first == next)
        try await fixture.owner.setSections([Section(id: "section", cells: [next])], animated: false)
        #expect(fixture.view.cellForItem(at: path) === original)
        #expect(events.configurations == initialConfigurations)
        #expect(bridge.collectionView(fixture.view, shouldSelectItemAt: path))
        #expect(bridge.collectionView(fixture.view, shouldDeselectItemAt: path))
        #expect(bridge.collectionView(fixture.view, shouldHighlightItemAt: path))

        bridge.collectionView(fixture.view, didSelectItemAt: path)
        bridge.collectionView(fixture.view, didDeselectItemAt: path)
        bridge.collectionView(fixture.view, didHighlightItemAt: path)
        bridge.collectionView(fixture.view, didUnhighlightItemAt: path)
        let point = CGPoint(x: 12, y: 34)
        let menu = bridge.collectionView(
            fixture.view,
            contextMenuConfigurationForItemAt: path,
            point: point
        )
        #expect(menu != nil)
        #expect(events.point == point)
        #expect(events.callbacks == [
            "next:select",
            "next:deselect",
            "next:highlight",
            "next:unhighlight",
            "next:menu"
        ])

        let invalid = IndexPath(item: 0, section: 1)
        #expect(!bridge.collectionView(fixture.view, shouldSelectItemAt: invalid))
        #expect(!bridge.collectionView(fixture.view, shouldDeselectItemAt: invalid))
        #expect(!bridge.collectionView(fixture.view, shouldHighlightItemAt: invalid))
    }

    @Test("A replacement registration does not overwrite a disappearing cell's lifecycle")
    func incompatibleRegistrationKeepsOldBinding() async throws {
        let fixture = Fixture()
        defer { fixture.window.isHidden = true }
        let events = Events()
        try await fixture.owner.setSections(
            [Section(id: "section", cells: [cell("same", token: "original", events: events)])],
            animated: false
        )
        let visible = try #require(fixture.view.cellForItem(at: .init(
            item: 0,
            section: 0
        )) as? ActionCell)
        let bridge = try #require(fixture.view.delegate as? CollectionViewBridge)
        fixture.installDisplayVersion([SectionSnapshot(
            id: "section",
            cells: [AnyCellPresenter(ReplacementPresenter(id: "same", events: events))]
        )])

        bridge.refreshVisibleBehaviors()
        visible.action?()
        bridge.collectionView(
            fixture.view,
            didEndDisplaying: visible,
            forItemAt: .init(item: 0, section: 0)
        )

        #expect(events.actions == ["original"])
        #expect(events.ended == ["original"])
    }

    @Test("A removed supplementary view retains the presenter for its final display callback")
    func removedSupplementaryKeepsDisplayBinding() async throws {
        let fixture = Fixture(header: true)
        defer { fixture.window.isHidden = true }
        let events = Events()
        let header = AnySupplementaryPresenter(Header(id: "old-header", events: events))
        try await fixture.owner.setSections([
            Section(
                id: "section",
                cells: [cell("cell", token: "cell", events: events)],
                supplementaryViews: [header]
            )
        ], animated: false)
        let path = IndexPath(item: 0, section: 0)
        let view = try #require(fixture.view.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader,
            at: path
        ))
        let bridge = try #require(fixture.view.delegate as? CollectionViewBridge)
        #expect(events.started.contains("old-header"))
        let replacementEvents = Events()
        fixture.installDisplayVersion([SectionSnapshot(
            id: "replacement",
            supplementaryViews: [AnySupplementaryPresenter(Header(
                id: "old-header",
                events: replacementEvents
            ))]
        )])
        // Supplementary IDs can repeat in another section. A disappearing
        // header still belongs to its original section's display lifecycle.
        bridge.refreshVisibleBehaviors()

        bridge.collectionView(
            fixture.view,
            didEndDisplayingSupplementaryView: view,
            forElementOfKind: UICollectionView.elementKindSectionHeader,
            at: path
        )

        #expect(events.ended == ["old-header"])
        #expect(replacementEvents.ended.isEmpty)
    }

    @Test(
        "Supplementary behavior refresh updates every active display and preserves unmatched-location recovery",
        arguments: [false, true]
    )
    func activeSupplementaryDisplaysUseLatestBehavior(matchingLocation: Bool) async throws {
        let fixture = Fixture(header: true)
        defer { fixture.window.isHidden = true }
        let events = Events()
        let path = IndexPath(item: 0, section: 0)
        let kind = UICollectionView.elementKindSectionHeader
        let first = AnySupplementaryPresenter(Header(id: "header", events: events, token: "first"))
        try await fixture.owner.setSections(
            [Section(id: "section", cells: [], supplementaryViews: [first])],
            animated: false
        )
        let view = try #require(fixture.view.supplementaryView(
            forElementKind: kind,
            at: path
        ) as? ActionHeader)
        let bridge = try #require(fixture.view.delegate as? CollectionViewBridge)
        bridge.collectionView(
            fixture.view,
            willDisplaySupplementaryView: view,
            forElementKind: kind,
            at: path
        )
        #expect(events.started == ["first", "first"])
        let configurations = events.configurationCount

        let latest = AnySupplementaryPresenter(Header(
            id: "header",
            events: events,
            token: "latest"
        ))
        fixture.installDisplayVersion([SectionSnapshot(id: "section", supplementaryViews: [latest])])
        bridge.refreshVisibleBehaviors()
        view.action?()

        let endPath = matchingLocation ? path : IndexPath(item: 9, section: 9)
        let endKind = matchingLocation ? kind : "missing-kind"
        bridge.collectionView(
            fixture.view,
            didEndDisplayingSupplementaryView: view,
            forElementOfKind: endKind,
            at: endPath
        )
        bridge.collectionView(
            fixture.view,
            didEndDisplayingSupplementaryView: view,
            forElementOfKind: endKind,
            at: endPath
        )
        bridge.collectionView(
            fixture.view,
            didEndDisplayingSupplementaryView: view,
            forElementOfKind: endKind,
            at: endPath
        )
        #expect(events.ended == ["latest", "latest"])
        #expect(events.actions == ["latest"])
        #expect(events.configurationCount == configurations)
    }

    @Test("A prepared cell keeps its display binding when configuration reenters the bridge")
    func preparedCellKeepsBindingDuringReentrantConfiguration() async throws {
        let fixture = Fixture()
        defer { fixture.window.isHidden = true }
        let events = Events()
        let path = IndexPath(item: 0, section: 0)
        try await fixture.owner.setSections(
            [Section(id: "section", cells: [cell("same", token: "first", events: events)])],
            animated: false
        )
        let view = try #require(fixture.view.cellForItem(at: path) as? ActionCell)
        let bridge = try #require(fixture.view.delegate as? CollectionViewBridge)
        fixture.view.contentOffset = CGPoint(x: 0, y: 1_000)
        fixture.view.layoutIfNeeded()
        try #require(!fixture.view.indexPathsForVisibleItems.contains(path))
        #expect(events.ended == ["first"])

        let nested = cell("same", token: "nested", events: events, content: "changed")
        let outer = AnyCellPresenter(ActionPresenter(
            id: "same",
            token: "outer",
            events: events,
            content: "changed",
            onConfigure: { cell in
                fixture.installDisplayVersion([SectionSnapshot(id: "section", cells: [nested])])
                bridge.collectionView(fixture.view, willDisplay: cell, forItemAt: path)
            }
        ))
        fixture.installDisplayVersion([SectionSnapshot(id: "section", cells: [outer])])
        bridge.collectionView(fixture.view, willDisplay: view, forItemAt: path)
        bridge.collectionView(fixture.view, didEndDisplaying: view, forItemAt: path)
        bridge.collectionView(fixture.view, didEndDisplaying: view, forItemAt: path)

        #expect(events.started == ["first", "nested", "outer"])
        #expect(events.ended == ["first", "nested", "outer"])
        #expect(events.configurationCount == 2)
    }

    @Test(
        "Prepared cells refresh offscreen and can redisplay without dequeue",
        arguments: [false, true]
    )
    func preparedCellUsesLatestPresenter(contentChanges: Bool) async throws {
        let fixture = Fixture()
        defer { fixture.window.isHidden = true }
        let view = fixture.view
        let owner = fixture.owner
        let bridge = try #require(view.delegate as? CollectionViewBridge)
        let events = Events()
        let original = cell("prepared", token: "first", events: events, content: "original")
        try await owner.setSections([Section(id: "section", cells: [original])], animated: false)
        let path = IndexPath(item: 0, section: 0)
        let prepared = try #require(view.cellForItem(at: path) as? ActionCell)
        #expect(events.started == ["first"])

        // Let UIKit create and finish displaying the actual cell. Holding the
        // view models UIKit's prepared lifetime; no out-of-band dequeue occurs.
        view.contentOffset = CGPoint(x: 0, y: 1_000)
        view.layoutIfNeeded()
        try #require(!view.indexPathsForVisibleItems.contains(path))
        #expect(events.ended == ["first"])
        let configurations = events.configurationCount

        let content = contentChanges ? "changed" : "original"
        let current = cell("prepared", token: "latest", events: events, content: content)
        fixture.installDisplayVersion([SectionSnapshot(id: "section", cells: [current])])
        bridge.refreshVisibleBehaviors()
        // Drive redisplay independently of dequeue, which UIKit permits for an
        // already prepared view. The visible-only refresh above cannot reach it.
        bridge.collectionView(view, willDisplay: prepared, forItemAt: path)
        prepared.action?()
        bridge.collectionView(view, didEndDisplaying: prepared, forItemAt: path)

        #expect(prepared.content == content)
        #expect(events.configurationCount == configurations + (contentChanges ? 1 : 0))
        #expect(events.actions == ["latest"])
        #expect(events.started == ["first", "latest"])
        #expect(events.ended == ["first", "latest"])

        let redisplayed = cell("prepared", token: "redisplayed", events: events, content: content)
        fixture.installDisplayVersion([SectionSnapshot(id: "section", cells: [redisplayed])])
        bridge.refreshVisibleBehaviors()
        bridge.collectionView(view, willDisplay: prepared, forItemAt: path)
        prepared.action?()
        bridge.collectionView(view, didEndDisplaying: prepared, forItemAt: path)

        #expect(events.actions == ["latest", "redisplayed"])
        #expect(events.started == ["first", "latest", "redisplayed"])
        #expect(events.ended == ["first", "latest", "redisplayed"])
    }

    @Test(
        "Prepared supplementaries refresh and can redisplay without dequeue",
        arguments: [false, true]
    )
    func preparedSupplementaryUsesLatestPresenter(contentChanges: Bool) async throws {
        let fixture = Fixture(header: true)
        defer { fixture.window.isHidden = true }
        let view = fixture.view
        let owner = fixture.owner
        let bridge = try #require(view.delegate as? CollectionViewBridge)
        let events = Events()
        let original = AnySupplementaryPresenter(Header(
            id: "header",
            events: events,
            token: "first",
            content: "original"
        ))
        try await owner.setSections(
            [Section(id: "section", cells: [], supplementaryViews: [original])],
            animated: false
        )
        let path = IndexPath(item: 0, section: 0)
        let kind = UICollectionView.elementKindSectionHeader
        let prepared = try #require(view.supplementaryView(
            forElementKind: kind,
            at: path
        ) as? ActionHeader)
        #expect(events.started == ["first"])

        view.contentOffset = CGPoint(x: 0, y: 1_000)
        view.layoutIfNeeded()
        try #require(!view.indexPathsForVisibleSupplementaryElements(ofKind: kind).contains(path))
        #expect(events.ended == ["first"])
        let configurations = events.configurationCount

        let content = contentChanges ? "changed" : "original"
        let current = AnySupplementaryPresenter(Header(
            id: "header",
            events: events,
            token: "latest",
            content: content
        ))
        fixture.installDisplayVersion([SectionSnapshot(
            id: "section",
            supplementaryViews: [current]
        )])
        bridge.refreshVisibleBehaviors()
        bridge.collectionView(
            view,
            willDisplaySupplementaryView: prepared,
            forElementKind: kind,
            at: path
        )
        prepared.action?()
        bridge.collectionView(
            view,
            didEndDisplayingSupplementaryView: prepared,
            forElementOfKind: kind,
            at: path
        )

        #expect(prepared.content == content)
        #expect(events.configurationCount == configurations + (contentChanges ? 1 : 0))
        #expect(events.actions == ["latest"])
        #expect(events.started == ["first", "latest"])
        #expect(events.ended == ["first", "latest"])

        let redisplayed = AnySupplementaryPresenter(Header(
            id: "header",
            events: events,
            token: "redisplayed",
            content: content
        ))
        fixture.installDisplayVersion([SectionSnapshot(
            id: "section",
            supplementaryViews: [redisplayed]
        )])
        bridge.refreshVisibleBehaviors()
        bridge.collectionView(
            view,
            willDisplaySupplementaryView: prepared,
            forElementKind: kind,
            at: path
        )
        prepared.action?()
        bridge.collectionView(
            view,
            didEndDisplayingSupplementaryView: prepared,
            forElementOfKind: kind,
            at: path
        )

        #expect(events.actions == ["latest", "redisplayed"])
        #expect(events.started == ["first", "latest", "redisplayed"])
        #expect(events.ended == ["first", "latest", "redisplayed"])
    }

    @Test("Missing cell content dequeues an inert view and reports after UIKit returns")
    func missingCellFallback() async throws {
        let fixture = Fixture()
        defer { fixture.window.isHidden = true }
        let bridge = try #require(fixture.view.delegate as? CollectionViewBridge)
        let events = Events()
        let globalEvents = GlobalEvents()
        fixture.owner.eventHandler = globalEvents
        let source = MissingCellDataSource(bridge: bridge)
        let ownedLayout = fixture.view.collectionViewLayout
        fixture.view.setCollectionViewLayout(UICollectionViewCompositionalLayout { _, environment in
            testSectionLayout(environment: environment)
        }, animated: false)
        var insideLayout = false
        var diagnostics: [CollectionDiagnostic] = []
        await withCheckedContinuation { continuation in
            fixture.owner.onDiagnostic = { diagnostic in
                #expect(!insideLayout)
                diagnostics.append(diagnostic)
                if diagnostics.count == 1 { continuation.resume() }
            }
            // UIKit sees one item, while the bridge has no presenter for it.
            // The dequeue occurs in a real UIKit request, not a manual callback.
            insideLayout = true
            fixture.view.dataSource = source
            fixture.view.reloadData()
            fixture.view.layoutIfNeeded()
            insideLayout = false
        }
        let path = IndexPath(item: 0, section: 0)
        let fallback = try #require(fixture.view.cellForItem(at: path))
        #expect(!fallback.isUserInteractionEnabled)
        #expect(fallback.contentView.subviews.isEmpty)
        #expect(diagnostics.first?.reason == .missingCell(section: 0, item: 0))
        #expect(diagnostics.first?.recovery == .displayedEmptyView)

        // Even when a presenter subsequently occupies the path, a fallback cell
        // must never forward its selection or display events to that presenter.
        fixture.installDisplayVersion([SectionSnapshot(
            id: "section",
            cells: [cell("new", token: "new", events: events)]
        )])
        #expect(!bridge.collectionView(fixture.view, shouldSelectItemAt: path))
        #expect(!bridge.collectionView(fixture.view, shouldHighlightItemAt: path))
        bridge.collectionView(fixture.view, didSelectItemAt: path)
        bridge.collectionView(fixture.view, willDisplay: fallback, forItemAt: path)
        #expect(events.started.isEmpty && events.selected.isEmpty &&
            globalEvents.selectedIds.isEmpty)

        fixture.view.dataSource = fixture.defaultSource
        fixture.view.setCollectionViewLayout(ownedLayout, animated: false)
        try await fixture.owner.setSections(
            [Section(id: "section", cells: [cell("new", token: "new", events: events)])],
            animated: false,
            mode: .reload
        )
        #expect(fixture.view.cellForItem(at: path) is ActionCell)
        #expect(bridge.collectionView(fixture.view, shouldSelectItemAt: path))
        bridge.collectionView(fixture.view, didSelectItemAt: path)
        #expect(events.selected == ["new"])
        #expect(globalEvents.selectedIds == [AnyHashable("new")])
        withExtendedLifetime(source) {}
    }

    @Test(
        "A layout-requested missing header uses an empty reusable view and later restores its presenter"
    )
    func missingSupplementaryFallback() async throws {
        let fixture = Fixture(header: true)
        defer { fixture.window.isHidden = true }
        let events = Events()
        var diagnostics: [CollectionDiagnostic] = []
        fixture.owner.onDiagnostic = { diagnostics.append($0) }
        let section = Section(id: "section", cells: [cell("one", token: "one", events: events)])
        section.requestsHeader = true
        try await fixture.owner.setSections([section], animated: false)
        let kind = UICollectionView.elementKindSectionHeader
        let path = IndexPath(item: 0, section: 0)
        let fallback = try #require(fixture.view.supplementaryView(forElementKind: kind, at: path))
        #expect(!fallback.isUserInteractionEnabled)
        #expect(fallback.subviews.isEmpty)
        #expect(diagnostics.contains { $0.reason == .missingSupplementary(
            kind: kind,
            section: 0,
            item: 0
        )
            && $0.recovery == .displayedEmptyView
        })

        let withHeader = section
        withHeader.supplementaryViews = [AnySupplementaryPresenter(Header(
            id: "header",
            events: events
        ))]
        try await fixture.owner.update([withHeader], animated: false)
        #expect(fixture.view.supplementaryView(forElementKind: kind, at: path) is ActionHeader)
        #expect(events.started.contains("header"))
    }

    private func cell(
        _ id: String,
        token: String,
        events: Events,
        content: String = ""
    ) -> AnyCellPresenter {
        AnyCellPresenter(ActionPresenter(id: id, token: token, events: events, content: content))
    }
}

@MainActor
private final class MissingCellDataSource: NSObject, UICollectionViewDataSource {
    let bridge: CollectionViewBridge
    init(bridge: CollectionViewBridge) { self.bridge = bridge }
    func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }
    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        1
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        bridge.cell(in: collectionView, at: indexPath, presenter: bridge.owner?.cellPresenter(at: indexPath))
    }
}

@MainActor
private final class Fixture {
    let window: UIWindow
    let view: UICollectionView
    let owner: CollectionOrchestrator
    let defaultSource: DefaultCollectionDataSource

    init(header: Bool = false) {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 50)
        if header { layout.headerReferenceSize = CGSize(width: 320, height: 30) }
        let frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        view = UICollectionView(frame: frame, collectionViewLayout: layout)
        owner = CollectionOrchestrator(collectionView: view)
        defaultSource = view.dataSource as! DefaultCollectionDataSource
        let controller = UIViewController()
        controller.view.frame = frame
        controller.view.addSubview(view)
        window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.isHidden = false
    }

    func installDisplayVersion(_ sections: [SectionSnapshot]) {
        for section in sections {
            for presenter in section.cells {
                owner.registry.prepare(presenter)
            }
            for presenter in section.supplementaryViews {
                owner.registry.prepare(presenter)
            }
        }
        defaultSource.sections = sections
    }
}

@MainActor
private final class Section: SectionPresenter {
    var requestsHeader = false
    let updates = SectionUpdateContext()
    let id: String
    var cells: [AnyCellPresenter]
    var supplementaryViews: [AnySupplementaryPresenter]

    init(id: String, cells: [AnyCellPresenter], supplementaryViews: [AnySupplementaryPresenter] = []) {
        self.id = id
        self.cells = cells
        self.supplementaryViews = supplementaryViews
    }

    func captureContent() -> DefaultSectionContent {
        var kinds = supplementaryViews.map(\.elementKind)
        if requestsHeader && !kinds.contains(UICollectionView.elementKindSectionHeader) {
            kinds.append(UICollectionView.elementKindSectionHeader)
        }
        return DefaultSectionContent(cells: cells, supplementaryViews: supplementaryViews) { [kinds] in
            testSectionLayout(kinds: kinds, environment: $0)
        }
    }
}

@MainActor
private final class Events {
    var configurationCount = 0
    var actions: [String] = []
    var selected: [String] = []
    var started: [String] = []
    var ended: [String] = []
}

@MainActor
private final class ActionCell: UICollectionViewCell {
    var action: (@MainActor () -> Void)?
    var content = ""
}

private struct ActionPresenter: CellPresenter,
    CellSelectionHandling,
    CellDisplayObserving
{
    let id: String
    let token: String
    let events: Events
    let content: String
    var onConfigure: (@MainActor (ActionCell) -> Void)? = nil

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.content == rhs.content }
    func configure(_ cell: ActionCell) {
        events.configurationCount += 1
        cell.content = content
        onConfigure?(cell)
    }

    func setBehaviors(_ cell: ActionCell) { cell.action = { events.actions.append(token) } }
    func didSelect(_ cell: ActionCell) { events.selected.append(token) }
    func willDisplay(_ cell: ActionCell) { events.started.append(token) }
    func didEndDisplaying(_ cell: ActionCell) { events.ended.append(token) }
}

private struct StaticPresenter: CellPresenter {
    let id: String
    static func == (lhs: Self, rhs: Self) -> Bool { true }
    func configure(_ cell: ActionCell) { cell.content = "Static" }
    func setBehaviors(_ cell: ActionCell) { cell.action = nil }
}

@MainActor
private final class InteractionEvents {
    var configurations = 0
    var callbacks: [String] = []
    var point: CGPoint?
}

private struct InteractionPresenter: CellSelectionHandling,
    CellHighlightHandling,
    CellContextMenuProviding
{
    let id = "interactive"
    let token: String
    let allowed: Bool
    let events: InteractionEvents
    var shouldSelect: Bool { allowed }
    var shouldDeselect: Bool { allowed }
    var shouldHighlight: Bool { allowed }
    static func == (lhs: Self, rhs: Self) -> Bool { true }
    func configure(_ cell: ActionCell) {
        cell.content = "Interactive"
        events.configurations += 1
    }

    func didSelect(_ cell: ActionCell) { events.callbacks.append("\(token):select") }
    func didDeselect(_ cell: ActionCell) { events.callbacks.append("\(token):deselect") }
    func didHighlight(_ cell: ActionCell) { events.callbacks.append("\(token):highlight") }
    func didUnhighlight(_ cell: ActionCell) { events.callbacks.append("\(token):unhighlight") }
    func contextMenuConfiguration(
        for cell: ActionCell,
        at point: CGPoint
    ) -> UIContextMenuConfiguration? {
        events.point = point
        events.callbacks.append("\(token):menu")
        return UIContextMenuConfiguration(
            identifier: nil,
            previewProvider: nil,
            actionProvider: nil
        )
    }
}

@MainActor
private final class ReplacementCell: UICollectionViewCell {}

private struct ReplacementPresenter: CellPresenter, CellDisplayObserving {
    let id: String
    let events: Events
    static func == (lhs: Self, rhs: Self) -> Bool { true }
    func configure(_ cell: ReplacementCell) {}
    func didEndDisplaying(_ cell: ReplacementCell) { events.ended.append("replacement") }
}

@MainActor
private final class ActionHeader: UICollectionReusableView {
    var action: (@MainActor () -> Void)?
    var content = ""
}

private struct Header: SupplementaryPresenter, SupplementaryDisplayObserving {
    let id: String
    let events: Events
    var token: String? = nil
    var content = ""
    var elementKind: String { UICollectionView.elementKindSectionHeader }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.content == rhs.content }
    func configure(_ view: ActionHeader) {
        events.configurationCount += 1
        view.content = content
    }

    func setBehaviors(_ view: ActionHeader) { view.action = { events.actions.append(token ?? id) } }
    func willDisplay(_ view: ActionHeader) { events.started.append(token ?? id) }
    func didEndDisplaying(_ view: ActionHeader) { events.ended.append(token ?? id) }
}

private struct StaticHeader: SupplementaryPresenter {
    let id: String
    var elementKind: String { Self.headerKind }
    static func == (lhs: Self, rhs: Self) -> Bool { true }
    func configure(_ view: ActionHeader) { view.content = "Static" }
    func setBehaviors(_ view: ActionHeader) { view.action = nil }
}

@MainActor
private final class GlobalEvents: CollectionEventHandler {
    var selectedIds: [AnyHashable] = []
    var sectionIds: [AnyHashable] = []
    func didSelect(presenter: AnyCellPresenter, in sectionId: AnyHashable) {
        selectedIds.append(presenter.id)
        sectionIds.append(sectionId)
    }
}

@MainActor
private final class ForwardingDelegate: NSObject, UICollectionViewDelegateFlowLayout {
    var scrollCount = 0
    var velocity: CGPoint?
    func scrollViewDidScroll(_ scrollView: UIScrollView) { scrollCount += 1 }
    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool { false }
    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        self.velocity = velocity
        targetContentOffset.pointee = CGPoint(x: 7, y: 11)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize { CGSize(width: 91, height: 37) }
}
