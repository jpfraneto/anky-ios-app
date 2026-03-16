//
//  WritingSessionStore.swift
//  Anky
//

import Foundation

struct StoredWritingDraft: Codable, Equatable {
    let sessionId: String
    let prompt: String
    let text: String
    let sessionElapsed: Double
    let livesRemaining: Int
    let keystrokeDeltas: [Double]
    let wasInterrupted: Bool
    let updatedAt: Date
}

enum WritingSessionStore {
    private static let draftKey = "anky.writer.current-draft.v2"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func loadDraft() -> StoredWritingDraft? {
        guard let data = UserDefaults.standard.data(forKey: draftKey) else { return nil }
        return try? decoder.decode(StoredWritingDraft.self, from: data)
    }

    static func saveDraft(_ draft: StoredWritingDraft) {
        guard let data = try? encoder.encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: draftKey)
    }

    static func clearDraft() {
        UserDefaults.standard.removeObject(forKey: draftKey)
    }

    static func hasDraft() -> Bool {
        loadDraft() != nil
    }
}
