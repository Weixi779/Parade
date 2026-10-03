// Created by weixi on 2026/09/17.

/// An identified algorithm input. Identity matches occurrences; `Equatable`
/// compares the content of a matched occurrence independently of UI execution.
public protocol DiffableElement: Equatable {
    associatedtype Id: Hashable
    var id: Id { get }
}
