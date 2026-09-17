//
//  SupplementaryDisplayObserving.swift
//  Parade
//
//  Created by weixi on 2026/9/17.
//

import UIKit

/// Opts a supplementary presenter into view visibility callbacks.
/// These callbacks do not define the item's lifetime or own asynchronous work.
public protocol SupplementaryDisplayObserving<View>: SupplementaryPresenter {
    @MainActor func willDisplay(_ view: View)
    @MainActor func didEndDisplaying(_ view: View)
}

public extension SupplementaryDisplayObserving {
    func willDisplay(_ view: View) {}
    func didEndDisplaying(_ view: View) {}
}

@MainActor
extension SupplementaryDisplayObserving {
    func dispatchWillDisplay(to rawView: UICollectionReusableView) {
        guard let view = rawView as? View else { return }
        willDisplay(view)
    }

    func dispatchDidEndDisplaying(to rawView: UICollectionReusableView) {
        guard let view = rawView as? View else { return }
        didEndDisplaying(view)
    }
}
