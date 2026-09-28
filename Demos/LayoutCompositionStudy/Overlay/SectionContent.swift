// Created by weixi on 2026/10/02.

import UIKit

public protocol SectionContent {
    associatedtype Layout
    var cells: [AnyCellPresenter] { get }
    var supplementaryViews: [AnySupplementaryPresenter] { get }
    var layout: Layout { get }
}

public extension SectionContent {
    var supplementaryViews: [AnySupplementaryPresenter] { [] }
}

public struct LayoutContent<Layout>: SectionContent {
    public let cells: [AnyCellPresenter]
    public let supplementaryViews: [AnySupplementaryPresenter]
    public let layout: Layout

    public init(cells: [AnyCellPresenter], supplementaryViews: [AnySupplementaryPresenter] = [], layout: Layout) {
        self.cells = cells
        self.supplementaryViews = supplementaryViews
        self.layout = layout
    }
}

final class SectionLayoutSnapshot<Layout> {
    let value: Layout
    init(_ value: Layout) { self.value = value }
}
