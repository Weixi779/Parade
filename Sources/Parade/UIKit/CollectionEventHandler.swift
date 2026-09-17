// Created by weixi on 2026/09/17.

import UIKit

/// Collection-wide selection events, in addition to each presenter's callbacks.
///
/// The application retains this handler and owns navigation and business actions.
@MainActor
public protocol CollectionEventHandler: AnyObject {
    func didSelect(presenter: AnyCellPresenter, in sectionId: AnyHashable)
    func didDeselect(presenter: AnyCellPresenter, in sectionId: AnyHashable)
}

extension CollectionEventHandler {
    public func didSelect(presenter: AnyCellPresenter, in sectionId: AnyHashable) {}
    public func didDeselect(presenter: AnyCellPresenter, in sectionId: AnyHashable) {}
}
