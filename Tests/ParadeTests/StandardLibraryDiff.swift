// Created by weixi on 2026/09/17.

import Parade

/// A second implementation using only the public contract. CollectionDifference
/// chooses sequence moves; global identity matching adds cross-section transfers.
struct StandardLibraryDiff: SectionedDiffAlgorithm {
    func diff<Section: DiffableSection>(from source: [Section],
                                        to target: [Section]) throws -> SectionedChanges {
        let sourceSections = Dictionary(uniqueKeysWithValues: source.enumerated().map { (
            $0.element.id,
            $0.offset
        ) })
        let sourceItems = locations(in: source)
        let targetItems = locations(in: target)
        var changes = SectionedChanges()
        for change in target.map(\.id).difference(from: source.map(\.id)).inferringMoves() {
            switch change {
            case let .remove(offset, _, destination):
                if let destination { changes.movedSections.append((from: offset, to: destination)) }
                else { changes.deletedSections.insert(offset) }
            case let .insert(offset, _, origin):
                if origin == nil { changes.insertedSections.insert(offset) }
            }
        }
        for (section, value) in source.enumerated() {
            for (item, old) in value.items.enumerated() where targetItems[old.id] == nil {
                changes.deletedItems.append(.init(section: section, item: item))
            }
        }
        for (section, value) in target.enumerated() {
            if let origin = sourceSections[value.id], !source[origin].isContentEqual(to: value) {
                changes.updatedSections.insert(section)
            }
            for (item, new) in value.items.enumerated() {
                let destination = ItemLocation(section: section, item: item)
                guard let origin = sourceItems[new.id] else {
                    changes.insertedItems.append(destination)
                    continue
                }
                if source[origin.section].id != value.id {
                    changes.movedItems.append((from: origin, to: destination))
                }
                if source[origin.section].items[origin.item] != new {
                    changes.updatedItems.append(destination)
                }
            }
            guard let origin = sourceSections[value.id] else { continue }
            let oldIds = source[origin].items.compactMap { item -> Section.Item.Id? in
                guard let destination = targetItems[item.id],
                      destination.section == section else { return nil }
                return item.id
            }
            let newIds = value.items.compactMap { item -> Section.Item.Id? in
                guard let previous = sourceItems[item.id],
                      previous.section == origin else { return nil }
                return item.id
            }
            for change in newIds.difference(from: oldIds).inferringMoves() {
                if case let .remove(_, id, .some(_)) = change {
                    changes.movedItems.append((from: sourceItems[id]!, to: targetItems[id]!))
                }
            }
        }
        return changes
    }

    private func locations<Section: DiffableSection>(in sections: [Section])
        -> [Section.Item.Id: ItemLocation] {
        var result: [Section.Item.Id: ItemLocation] = [:]
        for (section, value) in sections.enumerated() {
            for (item, value) in value.items.enumerated() {
                result[value.id] = ItemLocation(section: section, item: item)
            }
        }
        return result
    }
}
