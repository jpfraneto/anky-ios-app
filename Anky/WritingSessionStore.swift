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

struct LiveWritingSessionSnapshot: Codable, Equatable {
    let sessionId: String
    let text: String
    let sessionElapsed: Double
    let keystrokeDeltas: [Double]
    let updatedAt: Date
    let firstKeystrokeEpochMs: Int64?
    let partialAnkyFilePath: String?
}

enum WritingSessionStore {
    private static let draftKey = "anky.writer.current-draft.v2"
    private static let liveSnapshotKey = "anky.writer.live-session.v1"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
    private static var pendingLiveSave: DispatchWorkItem?

    // MARK: - Legacy structured draft (used by WritingFlowModel / onboarding)

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

    // MARK: - Live session checkpoint (debounced, restored by ChatViewModel)

    private static let liveDir: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("live_sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func liveFile(for sessionId: String) -> URL {
        liveDir.appendingPathComponent("\(sessionId).txt")
    }

    /// Legacy helper preserved for existing call sites that only know about text.
    static func checkpoint(sessionId: String, text: String) {
        scheduleLiveSave(
            LiveWritingSessionSnapshot(
                sessionId: sessionId,
                text: text,
                sessionElapsed: 0,
                keystrokeDeltas: [],
                updatedAt: .now,
                firstKeystrokeEpochMs: nil,
                partialAnkyFilePath: nil
            )
        )
    }

    static func scheduleLiveSave(
        _ snapshot: LiveWritingSessionSnapshot,
        partialSessionString: String? = nil,
        debounce: TimeInterval = 0.3
    ) {
        pendingLiveSave?.cancel()

        let workItem = DispatchWorkItem {
            let partialAnkyFilePath: String?
            if let partialSessionString,
               let firstKeystrokeEpochMs = snapshot.firstKeystrokeEpochMs {
                do {
                    let partialURL = try AnkySessionFileStore.writePartialSession(
                        sessionString: partialSessionString,
                        sessionId: snapshot.sessionId,
                        firstKeystrokeEpochMs: firstKeystrokeEpochMs
                    )
                    partialAnkyFilePath = partialURL.path
                } catch {
                    print("[AnkyFile] Failed to write partial session file: \(error.localizedDescription)")
                    partialAnkyFilePath = snapshot.partialAnkyFilePath
                }
            } else {
                partialAnkyFilePath = snapshot.partialAnkyFilePath
            }

            let persistedSnapshot = LiveWritingSessionSnapshot(
                sessionId: snapshot.sessionId,
                text: snapshot.text,
                sessionElapsed: snapshot.sessionElapsed,
                keystrokeDeltas: snapshot.keystrokeDeltas,
                updatedAt: snapshot.updatedAt,
                firstKeystrokeEpochMs: snapshot.firstKeystrokeEpochMs,
                partialAnkyFilePath: partialAnkyFilePath
            )

            if let data = try? Self.encoder.encode(persistedSnapshot) {
                UserDefaults.standard.set(data, forKey: Self.liveSnapshotKey)
            }

            let url = Self.liveFile(for: persistedSnapshot.sessionId)
            try? persistedSnapshot.text.write(to: url, atomically: false, encoding: .utf8)
        }

        pendingLiveSave = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: workItem)
    }

    static func loadLiveSessionSnapshot() -> LiveWritingSessionSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: liveSnapshotKey),
              var snapshot = try? decoder.decode(LiveWritingSessionSnapshot.self, from: data) else {
            return nil
        }

        let url = liveFile(for: snapshot.sessionId)
        if let restoredText = try? String(contentsOf: url, encoding: .utf8),
           !restoredText.isEmpty,
           restoredText != snapshot.text {
            snapshot = LiveWritingSessionSnapshot(
                sessionId: snapshot.sessionId,
                text: restoredText,
                sessionElapsed: snapshot.sessionElapsed,
                keystrokeDeltas: snapshot.keystrokeDeltas,
                updatedAt: snapshot.updatedAt,
                firstKeystrokeEpochMs: snapshot.firstKeystrokeEpochMs,
                partialAnkyFilePath: snapshot.partialAnkyFilePath
            )
        }

        return snapshot.text.isEmpty ? nil : snapshot
    }

    static func hasRecoverableLiveSession() -> Bool {
        loadLiveSessionSnapshot() != nil
    }

    static func clearLiveSession(sessionId: String? = nil) {
        let resolvedSessionID = sessionId ?? loadLiveSessionSnapshot()?.sessionId
        pendingLiveSave?.cancel()
        pendingLiveSave = nil
        UserDefaults.standard.removeObject(forKey: liveSnapshotKey)

        guard let resolvedSessionID else { return }

        let url = liveFile(for: resolvedSessionID)
        try? FileManager.default.removeItem(at: url)
    }
}
