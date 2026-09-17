//
//  SupplementaryPresenterTests.swift
//  ParadeTests
//
//  Created by weixi on 2026/9/17.
//

import Testing
import UIKit
@testable import Parade

@MainActor
@Suite("Supplementary presenter capabilities")
struct SupplementaryPresenterTests {
    @Test("Optional display callbacks preserve the concrete view through generic erasure")
    func typedDisplayDispatch() throws {
        var events: [String] = []
        let erased = erase(ObservedHeader(onDisplay: { events.append($0) }))
        let observer =
            try #require(erased.underlyingPresenter as? any SupplementaryDisplayObserving)
        let view = HeaderView(frame: .zero)
        erased.configure(view)

        observer.dispatchWillDisplay(to: view)
        observer.dispatchDidEndDisplaying(to: view)
        let incompatible = UICollectionReusableView(frame: .zero)
        erased.configure(incompatible)
        erased.setBehaviors(incompatible)
        observer.dispatchWillDisplay(to: incompatible)
        observer.dispatchDidEndDisplaying(to: incompatible)

        // This presenter implements only willDisplay; the companion callback is optional.
        #expect(events == ["Header"])
    }

    @Test("Same-named methods do not opt a supplementary presenter into display observation")
    func displayRequiresConformance() {
        var events: [String] = []
        let erased = erase(UnclaimedHeader(onEvent: { events.append($0) }))
        let observer = erased.underlyingPresenter as? any SupplementaryDisplayObserving
        let view = HeaderView(frame: .zero)
        observer?.dispatchWillDisplay(to: view)
        observer?.dispatchDidEndDisplaying(to: view)

        #expect(observer == nil)
        #expect(events.isEmpty)
    }

    @Test("A consumer-only supplementary capability needs no registration in the eraser")
    func consumerDefinedCapability() throws {
        var events: [String] = []
        let erased = erase(ConsumerHeader(onAction: { events.append($0) }))
        let handler =
            try #require(erased.underlyingPresenter as? any ConsumerSupplementaryActionHandling)
        let view = HeaderView(frame: .zero)
        view.title = "Consumer action"
        handler.dispatchAction(to: view)
        handler.dispatchAction(to: UICollectionReusableView(frame: .zero))

        #expect(events == ["Consumer action"])
        #expect(erased.underlyingPresenter as? any SupplementaryDisplayObserving == nil)
        let ordinary = erase(ObservedHeader(onDisplay: { _ in }))
        #expect(ordinary.underlyingPresenter as? any ConsumerSupplementaryActionHandling == nil)
        #expect(erased.registrationKey == ordinary.registrationKey)
        #expect(erased != ordinary)
        #expect(ordinary != erased)
    }

    private func erase<P: SupplementaryPresenter>(_ presenter: P) -> AnySupplementaryPresenter {
        AnySupplementaryPresenter(presenter)
    }
}

@MainActor
private final class HeaderView: UICollectionReusableView {
    var title = ""
}

private struct ObservedHeader: SupplementaryDisplayObserving {
    let id = "header"
    var elementKind: String { Self.headerKind }
    let onDisplay: @MainActor (String) -> Void
    static func == (lhs: Self, rhs: Self) -> Bool { true }
    func configure(_ view: HeaderView) { view.title = "Header" }
    func willDisplay(_ view: HeaderView) { onDisplay(view.title) }
}

private struct UnclaimedHeader: SupplementaryPresenter {
    let id = "header"
    var elementKind: String { Self.headerKind }
    let onEvent: @MainActor (String) -> Void
    static func == (lhs: Self, rhs: Self) -> Bool { true }
    func configure(_ view: HeaderView) {}
    @MainActor func willDisplay(_ view: HeaderView) { onEvent("display") }
    @MainActor func didEndDisplaying(_ view: HeaderView) { onEvent("end") }
}

// This capability belongs to the test consumer; Parade has no knowledge of it.
private protocol ConsumerSupplementaryActionHandling: SupplementaryPresenter {
    @MainActor func performAction(_ view: View)
}

@MainActor
private extension ConsumerSupplementaryActionHandling {
    func dispatchAction(to rawView: UICollectionReusableView) {
        guard let view = rawView as? View else { return }
        performAction(view)
    }
}

private struct ConsumerHeader: ConsumerSupplementaryActionHandling {
    let id = "header"
    var elementKind: String { Self.headerKind }
    let onAction: @MainActor (String) -> Void
    static func == (lhs: Self, rhs: Self) -> Bool { true }
    func configure(_ view: HeaderView) {}
    func performAction(_ view: HeaderView) { onAction(view.title) }
}
