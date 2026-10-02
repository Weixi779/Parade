// Created by weixi on 2026/10/02.

import UIKit

/// Subclass to implement a layout's section queries, including custom Swift protocols.
/// Parade installs and retains this object as the collection delegate. Create one
/// instance per collection; do not share it or replace collectionView.delegate.
///
/// Selection, context menus, display and scroll callbacks below are sealed: they
/// keep using Parade's presenters, event handler and scrollViewDelegate. Only add
/// the layout-specific callbacks required by your layout.
@MainActor
open class CollectionLayoutDelegate: NSObject, UICollectionViewDelegate {
    weak var bridge: CollectionViewBridge?

    override public init() {
        super.init()
    }
}

public extension CollectionLayoutDelegate {
    final func collectionView(
        _ collectionView: UICollectionView,
        shouldSelectItemAt indexPath: IndexPath
    ) -> Bool {
        bridge?.collectionView(collectionView, shouldSelectItemAt: indexPath) ?? false
    }

    final func collectionView(
        _ collectionView: UICollectionView,
        shouldDeselectItemAt indexPath: IndexPath
    ) -> Bool {
        bridge?.collectionView(collectionView, shouldDeselectItemAt: indexPath) ?? false
    }

    final func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        bridge?.collectionView(collectionView, didSelectItemAt: indexPath)
    }

    final func collectionView(
        _ collectionView: UICollectionView,
        didDeselectItemAt indexPath: IndexPath
    ) {
        bridge?.collectionView(collectionView, didDeselectItemAt: indexPath)
    }

    final func collectionView(
        _ collectionView: UICollectionView,
        shouldHighlightItemAt indexPath: IndexPath
    ) -> Bool {
        bridge?.collectionView(collectionView, shouldHighlightItemAt: indexPath) ?? false
    }

    final func collectionView(
        _ collectionView: UICollectionView,
        didHighlightItemAt indexPath: IndexPath
    ) {
        bridge?.collectionView(collectionView, didHighlightItemAt: indexPath)
    }

    final func collectionView(
        _ collectionView: UICollectionView,
        didUnhighlightItemAt indexPath: IndexPath
    ) {
        bridge?.collectionView(collectionView, didUnhighlightItemAt: indexPath)
    }

    final func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        bridge?.collectionView(collectionView, contextMenuConfigurationForItemAt: indexPath, point: point)
    }

    final func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        bridge?.collectionView(collectionView, willDisplay: cell, forItemAt: indexPath)
    }

    final func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        bridge?.collectionView(collectionView, didEndDisplaying: cell, forItemAt: indexPath)
    }

    final func collectionView(
        _ collectionView: UICollectionView,
        willDisplaySupplementaryView view: UICollectionReusableView,
        forElementKind elementKind: String,
        at indexPath: IndexPath
    ) {
        bridge?.collectionView(
            collectionView,
            willDisplaySupplementaryView: view,
            forElementKind: elementKind,
            at: indexPath
        )
    }

    final func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplayingSupplementaryView view: UICollectionReusableView,
        forElementOfKind elementKind: String,
        at indexPath: IndexPath
    ) {
        bridge?.collectionView(
            collectionView,
            didEndDisplayingSupplementaryView: view,
            forElementOfKind: elementKind,
            at: indexPath
        )
    }

    final func scrollViewDidScroll(_ scrollView: UIScrollView) {
        bridge?.scrollViewDidScroll(scrollView)
    }

    final func scrollViewDidZoom(_ scrollView: UIScrollView) {
        bridge?.scrollViewDidZoom(scrollView)
    }

    final func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        bridge?.scrollViewWillBeginDragging(scrollView)
    }

    final func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        bridge?.scrollViewWillEndDragging(scrollView, withVelocity: velocity, targetContentOffset: targetContentOffset)
    }

    final func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        bridge?.scrollViewDidEndDragging(scrollView, willDecelerate: decelerate)
    }

    final func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {
        bridge?.scrollViewWillBeginDecelerating(scrollView)
    }

    final func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        bridge?.scrollViewDidEndDecelerating(scrollView)
    }

    final func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        bridge?.scrollViewDidEndScrollingAnimation(scrollView)
    }

    final func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        bridge?.viewForZooming(in: scrollView)
    }

    final func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        bridge?.scrollViewWillBeginZooming(scrollView, with: view)
    }

    final func scrollViewDidEndZooming(
        _ scrollView: UIScrollView,
        with view: UIView?,
        atScale scale: CGFloat
    ) {
        bridge?.scrollViewDidEndZooming(scrollView, with: view, atScale: scale)
    }

    final func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        bridge?.scrollViewShouldScrollToTop(scrollView) ?? true
    }

    final func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        bridge?.scrollViewDidScrollToTop(scrollView)
    }

    final func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
        bridge?.scrollViewDidChangeAdjustedContentInset(scrollView)
    }
}
