// Created by weixi on 2026/09/17.

/// Compares two complete, captured section collections without performing UI work.
///
/// Implementations match identities, compare section content with `isContentEqual`
/// and item content with `==`, and return changes in the original input coordinates.
/// They must preserve retained identities, including transfers between deleted and
/// inserted sections. Move choices may differ; minimal moves are not required.
/// Inputs must remain stable for the duration of this synchronous call.
public protocol SectionedDiffAlgorithm {
    func diff<Section: DiffableSection>(
        from source: [Section],
        to target: [Section]
    ) throws -> SectionedChanges
}
