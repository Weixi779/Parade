// Created by weixi on 2026/09/17.

/// An identified presentation value. Identity matches occurrences; `Equatable`
/// determines whether a matched occurrence needs its visual content updated.
///
/// Use synthesized equality when all stored values participate. When a presenter
/// contains behavior closures, implement `static func ==` using its
/// presentation fields. Equal values still receive the latest behavior bindings.
public protocol DiffableElement: Equatable {
    associatedtype Id: Hashable
    var id: Id { get }
}

extension DiffableElement {
    func equals(_ other: any DiffableElement) -> Bool {
        guard type(of: self) == type(of: other), let other = other as? Self else { return false }
        return self == other
    }
}
