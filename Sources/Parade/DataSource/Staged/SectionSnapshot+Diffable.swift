// Created by weixi on 2026/10/03.

/// Adapts captured presentation values to the staged implementation's algorithm inputs.
extension AnyCellPresenter: DiffableElement {}

extension SectionSnapshot: DiffableSection {
    public var items: [AnyCellPresenter] { cells }

    public func isContentEqual(to other: Self) -> Bool {
        hasSameSupplementaryContent(as: other)
    }
}
