//
//  ArweaveStore.swift
//  Anky
//
//  Permanent text storage on Arweave via Irys (formerly Bundlr).
//  Every completed anky's text is uploaded here as a fallback guarantee
//  that the writing can never be lost, even if the backend goes away.
//
//  Uses Irys's free tier for small text uploads signed with the user's
//  Solana Ed25519 key.
//

import Foundation

struct ArweaveUploadResult: Codable {
    let id: String          // Arweave transaction ID
    let timestamp: Int?
}

struct PendingArweaveUpload: Codable, Identifiable, Equatable {
    let id: String          // sessionId
    let text: String
    let createdAt: Date
    var retryCount: Int

    init(sessionId: String, text: String) {
        self.id = sessionId
        self.text = text
        self.createdAt = .now
        self.retryCount = 0
    }
}

enum ArweaveStore {
    /// Irys node for Solana uploads.
    /// Uses the free gateway for uploads under 100KB.
    private static let irysURL = URL(string: "https://uploader.irys.xyz/upload")!
    private static let pendingKey = "anky.arweave.pending_uploads"
    private static let completedKey = "anky.arweave.completed"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    // MARK: - Upload

    /// Upload text to Arweave via Irys. Signed with the user's Solana key.
    /// Returns the Arweave transaction ID on success.
    static func upload(sessionId: String, text: String) async throws -> String {
        let textData = Data(text.utf8)

        // Sign the data with the user's Ed25519 key
        let signature = try SeedIdentityManager.shared.sign(message: textData)
        let walletAddress = try SeedIdentityManager.shared.walletAddress()

        // Build multipart upload to Irys
        let boundary = UUID().uuidString
        var request = URLRequest(url: irysURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // File field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(sessionId).txt\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/plain\r\n\r\n".data(using: .utf8)!)
        body.append(textData)
        body.append("\r\n".data(using: .utf8)!)

        // Tags
        let tags: [[String: String]] = [
            ["name": "Content-Type", "value": "text/plain"],
            ["name": "App-Name", "value": "Anky"],
            ["name": "Session-Id", "value": sessionId],
            ["name": "Wallet", "value": walletAddress],
            ["name": "Signature", "value": signature.base64EncodedString()],
        ]

        if let tagsData = try? JSONSerialization.data(withJSONObject: tags) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"tags\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
            body.append(tagsData)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ArweaveError.invalidResponse
        }

        if http.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw ArweaveError.uploadFailed(msg)
        }

        // Parse response for transaction ID
        if let result = try? JSONDecoder().decode(ArweaveUploadResult.self, from: data) {
            markCompleted(sessionId: sessionId, txId: result.id)
            return result.id
        }

        // Fallback: try to get "id" from JSON
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let txId = json["id"] as? String {
            markCompleted(sessionId: sessionId, txId: txId)
            return txId
        }

        throw ArweaveError.invalidResponse
    }

    // MARK: - Queue Management

    /// Queue a text for Arweave upload (when offline or upload fails).
    static func enqueue(sessionId: String, text: String) {
        var pending = loadPending()
        guard !pending.contains(where: { $0.id == sessionId }) else { return }
        pending.append(PendingArweaveUpload(sessionId: sessionId, text: text))
        savePending(pending)
        print("[ArweaveStore] Queued \(sessionId) for Arweave upload")
    }

    /// Retry all pending uploads. Returns count of successful uploads.
    static func retryPending() async -> Int {
        var pending = loadPending()
        guard !pending.isEmpty else { return 0 }

        var uploaded = 0
        var remaining: [PendingArweaveUpload] = []

        for var item in pending {
            do {
                _ = try await upload(sessionId: item.id, text: item.text)
                uploaded += 1
            } catch {
                item.retryCount += 1
                if item.retryCount < 15 {
                    remaining.append(item)
                }
                print("[ArweaveStore] Upload deferred \(item.id): \(error.localizedDescription)")
            }
        }

        savePending(remaining)
        return uploaded
    }

    /// Check if a session has been uploaded to Arweave.
    static func arweaveTxId(for sessionId: String) -> String? {
        loadCompleted()[sessionId]
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: pendingKey)
        UserDefaults.standard.removeObject(forKey: completedKey)
    }

    // MARK: - Private

    private static func markCompleted(sessionId: String, txId: String) {
        var completed = loadCompleted()
        completed[sessionId] = txId
        if let data = try? encoder.encode(completed) {
            UserDefaults.standard.set(data, forKey: completedKey)
        }
        // Remove from pending
        var pending = loadPending()
        pending.removeAll { $0.id == sessionId }
        savePending(pending)
    }

    private static func loadPending() -> [PendingArweaveUpload] {
        guard let data = UserDefaults.standard.data(forKey: pendingKey) else { return [] }
        return (try? decoder.decode([PendingArweaveUpload].self, from: data)) ?? []
    }

    private static func savePending(_ items: [PendingArweaveUpload]) {
        guard let data = try? encoder.encode(items) else { return }
        UserDefaults.standard.set(data, forKey: pendingKey)
    }

    private static func loadCompleted() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: completedKey) else { return [:] }
        return (try? decoder.decode([String: String].self, from: data)) ?? [:]
    }
}

enum ArweaveError: LocalizedError {
    case invalidResponse
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from Arweave gateway."
        case .uploadFailed(let msg): return "Arweave upload failed: \(msg)"
        }
    }
}
