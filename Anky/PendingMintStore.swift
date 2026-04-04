//
//  PendingMintStore.swift
//  Anky
//
//  Persistent queue for cNFT mints that failed (offline, error, etc).
//  Retries on next app launch or network reconnection.
//

import Foundation

struct PendingMint: Codable, Identifiable, Equatable {
    let id: String          // sessionId
    let createdAt: Date
    var retryCount: Int

    init(sessionId: String) {
        self.id = sessionId
        self.createdAt = .now
        self.retryCount = 0
    }
}

enum PendingMintStore {
    private static let storeKey = "anky.pending_mints"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// Add a session to the mint retry queue.
    static func enqueue(sessionId: String) {
        var pending = loadAll()
        guard !pending.contains(where: { $0.id == sessionId }) else { return }
        pending.append(PendingMint(sessionId: sessionId))
        save(pending)
    }

    /// Remove a session from the mint queue (mint succeeded or permanently failed).
    static func dequeue(sessionId: String) {
        var pending = loadAll()
        pending.removeAll { $0.id == sessionId }
        save(pending)
    }

    /// Load all pending mints.
    static func loadAll() -> [PendingMint] {
        guard let data = UserDefaults.standard.data(forKey: storeKey) else { return [] }
        return (try? decoder.decode([PendingMint].self, from: data)) ?? []
    }

    /// Retry all pending mints. Returns count of successful mints.
    @MainActor
    static func retryPending(appState: AppState) async -> Int {
        var pending = loadAll()
        guard !pending.isEmpty else { return 0 }

        guard let walletAddress = try? SeedIdentityManager.shared.walletAddress() else {
            return 0
        }

        var minted = 0
        var remaining: [PendingMint] = []

        for var mint in pending {
            do {
                let response = try await AnkyAPI.shared.mintMirror(
                    writingSessionId: mint.id,
                    recipient: walletAddress
                )
                if response.success || response.alreadyMinted == true {
                    if response.success {
                        appState.saveMirrorMint(response: response)
                    }
                    minted += 1
                    print("[PendingMintStore] Minted \(mint.id)")
                } else {
                    mint.retryCount += 1
                    if mint.retryCount < 10 {
                        remaining.append(mint)
                    }
                    print("[PendingMintStore] Failed \(mint.id): \(response.error ?? "unknown")")
                }
            } catch {
                mint.retryCount += 1
                if mint.retryCount < 10 {
                    remaining.append(mint)
                }
                print("[PendingMintStore] Deferred \(mint.id): \(error.localizedDescription)")
            }
        }

        save(remaining)
        return minted
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storeKey)
    }

    private static func save(_ mints: [PendingMint]) {
        guard let data = try? encoder.encode(mints) else { return }
        UserDefaults.standard.set(data, forKey: storeKey)
    }
}
