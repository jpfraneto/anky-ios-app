//
//  GeneratedAnkyStore.swift
//  Anky
//

import Foundation

enum GeneratedAnkyStore {
    private static let completedKey = "anky.generated.completed"
    private static let pendingKey = "anky.generated.pending"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func loadCompleted() -> [GeneratedAnky] {
        guard let data = UserDefaults.standard.data(forKey: completedKey) else { return [] }
        let items = (try? decoder.decode([GeneratedAnky].self, from: data)) ?? []
        return sort(items)
    }

    @discardableResult
    static func upsertCompleted(_ item: GeneratedAnky) -> [GeneratedAnky] {
        var items = loadCompleted().filter { $0.id != item.id }
        items.insert(item, at: 0)
        let sorted = sort(items)
        saveCompleted(sorted)
        return sorted
    }

    @discardableResult
    static func mergeCompleted(_ items: [GeneratedAnky]) -> [GeneratedAnky] {
        var mergedByID = Dictionary(uniqueKeysWithValues: loadCompleted().map { ($0.id, $0) })
        for item in items {
            mergedByID[item.id] = item
        }
        let sorted = sort(Array(mergedByID.values))
        saveCompleted(sorted)
        return sorted
    }

    static func loadPendingGenerationIDs() -> [String] {
        UserDefaults.standard.stringArray(forKey: pendingKey) ?? []
    }

    static func rememberPendingGeneration(id: String) {
        guard !id.isEmpty else { return }
        var ids = loadPendingGenerationIDs()
        guard !ids.contains(id) else { return }
        ids.append(id)
        UserDefaults.standard.set(ids, forKey: pendingKey)
    }

    static func forgetPendingGeneration(id: String) {
        let filtered = loadPendingGenerationIDs().filter { $0 != id }
        UserDefaults.standard.set(filtered, forKey: pendingKey)
    }

    private static func saveCompleted(_ items: [GeneratedAnky]) {
        guard let data = try? encoder.encode(items) else { return }
        UserDefaults.standard.set(data, forKey: completedKey)
    }

    private static func sort(_ items: [GeneratedAnky]) -> [GeneratedAnky] {
        items.sorted {
            ($0.createdAtDate ?? .distantPast) > ($1.createdAtDate ?? .distantPast)
        }
    }
}
