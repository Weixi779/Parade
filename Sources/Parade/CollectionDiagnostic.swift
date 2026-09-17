// Created by weixi on 2026/09/17.

/// A recoverable problem and the action Parade took. Delivery occurs outside
/// UIKit callbacks, after any active submission has settled its display state.
public struct CollectionDiagnostic: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case invalidUpdate(CollectionUpdateError)
        case invalidDiff(String)
        case missingCell(section: Int, item: Int)
        case missingSupplementary(kind: String, section: Int, item: Int)
    }

    public enum Recovery: Equatable, Sendable {
        case rejectedUpdate
        case reloadedTarget
        case displayedEmptyView
    }

    /// Positions in the submitted composition. A nil item identifies a section.
    public struct Location: Equatable, Sendable {
        public let section: Int
        public let item: Int?

        public init(section: Int, item: Int? = nil) {
            self.section = section
            self.item = item
        }
    }

    public let reason: Reason
    public let recovery: Recovery
    /// For duplicate input, the original position followed by the duplicate.
    public let locations: [Location]

    init(reason: Reason, recovery: Recovery, locations: [Location] = []) {
        self.reason = reason
        self.recovery = recovery
        self.locations = locations
    }
}
