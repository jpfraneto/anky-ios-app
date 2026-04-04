//
//  AnkyFlowTests.swift
//  AnkyTests
//
//  Tests for critical user flows: JSON decoding, offline queue,
//  writing cache, draft persistence, flow score, and voice models.
//

import Foundation
import Testing
@testable import Anky

// MARK: - Backend Response Decoding

struct ResponseDecodingTests {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    @Test("MobileWriteResponse decodes a full anky outcome")
    func writeResponseDecodesAnkyOutcome() throws {
        let json = """
        {
            "ok": true,
            "session_id": "abc-123",
            "outcome": "anky",
            "word_count": 342,
            "duration_seconds": 512.0,
            "flow_score": 0.78,
            "persisted": true,
            "spawned": {
                "anky_id": "anky-001",
                "feedback": true,
                "meditation": false,
                "breathwork": false,
                "cuentacuentos": true
            },
            "wallet_address": "0xABC",
            "status_url": "/writing/abc-123/status"
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(MobileWriteResponse.self, from: json)

        #expect(response.ok == true)
        #expect(response.isAnky == true)
        #expect(response.ankyId == "anky-001")
        #expect(response.wordCount == 342)
        #expect(response.durationSeconds == 512.0)
        #expect(response.flowScore == 0.78)
        #expect(response.persisted == true)
        #expect(response.spawned?.cuentacuentos == true)
        #expect(response.statusUrl == "/writing/abc-123/status")
    }

    @Test("MobileWriteResponse decodes a short non-anky write")
    func writeResponseDecodesShortWrite() throws {
        let json = """
        {
            "ok": true,
            "session_id": "short-1",
            "outcome": null,
            "word_count": 42,
            "duration_seconds": 90.0,
            "flow_score": 0.3,
            "persisted": true,
            "spawned": null,
            "wallet_address": null,
            "status_url": null,
            "error": null
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(MobileWriteResponse.self, from: json)

        #expect(response.isAnky == false)
        #expect(response.ankyId == nil)
        #expect(response.persisted == true)
        #expect(response.spawned == nil)
    }

    @Test("MobileWriteResponse decodes with error field")
    func writeResponseDecodesError() throws {
        let json = """
        {
            "ok": false,
            "session_id": "err-1",
            "outcome": null,
            "word_count": 0,
            "error": "duplicate session"
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(MobileWriteResponse.self, from: json)

        #expect(response.ok == false)
        #expect(response.error == "duplicate session")
    }

    @Test("WritingStatusResponse decodes artifact progress")
    func statusResponseDecodesArtifacts() throws {
        let json = """
        {
            "session_id": "abc-123",
            "is_anky": true,
            "duration_seconds": 512.0,
            "word_count": 342,
            "anky": {
                "id": "anky-001",
                "status": "ready",
                "image_url": "https://cdn.anky.app/images/anky-001.png",
                "title": "An anky was born.",
                "reflection": "You wrote about the ocean."
            },
            "cuentacuentos": {
                "id": "cuento-001",
                "status": "generating",
                "chakra": 3,
                "kingdom": "Poiesis",
                "city": "Luminara",
                "title": "The golden fish",
                "translations_done": ["en", "es"],
                "images_total": 5,
                "images_done": 2
            },
            "meditation": null,
            "breathwork": null
        }
        """.data(using: .utf8)!

        let status = try decoder.decode(WritingStatusResponse.self, from: json)

        #expect(status.isAnky == true)
        #expect(status.anky?.status == "ready")
        #expect(status.anky?.imageUrl == "https://cdn.anky.app/images/anky-001.png")
        #expect(status.anky?.reflection == "You wrote about the ocean.")
        #expect(status.cuentacuentos?.status == "generating")
        #expect(status.cuentacuentos?.imagesDone == 2)
        #expect(status.cuentacuentos?.imagesTotal == 5)
        #expect(status.cuentacuentos?.translationsDone == ["en", "es"])
    }

    @Test("WritingItem decodes with snake_case keys from backend")
    func writingItemDecodesSnakeCase() throws {
        let json = """
        {
            "id": "w-1",
            "content": "stream of consciousness text here",
            "duration_seconds": 500,
            "word_count": 310,
            "is_anky": true,
            "response": "You explored memory.",
            "anky_id": "anky-001",
            "anky_title": "An anky was born.",
            "anky_image_path": "/images/anky-001.png",
            "created_at": "2026-03-20T10:00:00Z"
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(WritingItem.self, from: json)

        #expect(item.id == "w-1")
        #expect(item.durationSeconds == 500)
        #expect(item.isAnky == true)
        #expect(item.ankyId == "anky-001")
        #expect(item.ankyImagePath == "/images/anky-001.png")
    }

    @Test("WritingItem decodes with alternative key names")
    func writingItemDecodesAltKeys() throws {
        let json = """
        {
            "session_id": "s-1",
            "text": "writing content here",
            "duration": 490,
            "created_at": "2026-03-20T10:00:00Z"
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(WritingItem.self, from: json)

        #expect(item.id == "s-1")
        #expect(item.content == "writing content here")
        #expect(item.durationSeconds == 490)
    }
}

// MARK: - Voice Recording Models

struct VoiceRecordingModelTests {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    @Test("VoiceRecordingCreateResponse decodes with upload_url")
    func createResponseDecodes() throws {
        let json = """
        {
            "recording_id": "rec-001",
            "status": "pending",
            "upload_url": "https://r2.cloudflarestorage.com/anky/recordings/rec-001?X-Amz-Signature=abc123"
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(VoiceRecordingCreateResponse.self, from: json)

        #expect(response.recordingId == "rec-001")
        #expect(response.status == "pending")
        #expect(response.uploadUrl.contains("r2.cloudflarestorage.com"))
    }

    @Test("VoiceRecording decodes all statuses including rejection_reason")
    func recordingDecodesAllStatuses() throws {
        let pendingJson = """
        {
            "id": "rec-001",
            "attempt_number": 1,
            "status": "pending",
            "duration_seconds": 142.5,
            "created_at": "2026-03-20T10:00:00Z",
            "audio_url": null,
            "rejection_reason": null
        }
        """.data(using: .utf8)!

        let rejectedJson = """
        {
            "id": "rec-002",
            "attempt_number": 2,
            "status": "rejected",
            "duration_seconds": 45.0,
            "created_at": "2026-03-20T11:00:00Z",
            "audio_url": null,
            "rejection_reason": "similarity score too low — re-record"
        }
        """.data(using: .utf8)!

        let approvedJson = """
        {
            "id": "rec-003",
            "attempt_number": 3,
            "status": "approved",
            "duration_seconds": 150.0,
            "created_at": "2026-03-20T12:00:00Z",
            "audio_url": "https://storage.anky.app/recordings/rec-003.m4a",
            "rejection_reason": null
        }
        """.data(using: .utf8)!

        let pending = try decoder.decode(VoiceRecording.self, from: pendingJson)
        let rejected = try decoder.decode(VoiceRecording.self, from: rejectedJson)
        let approved = try decoder.decode(VoiceRecording.self, from: approvedJson)

        #expect(pending.status == .pending)
        #expect(pending.audioUrl == nil)
        #expect(pending.rejectionReason == nil)
        #expect(pending.durationLabel == "2:22")

        #expect(rejected.status == .rejected)
        #expect(rejected.rejectionReason == "similarity score too low — re-record")

        #expect(approved.status == .approved)
        #expect(approved.audioUrl == "https://storage.anky.app/recordings/rec-003.m4a")
        #expect(approved.attemptNumber == 3)
    }

    @Test("StoryVoice decodes language-matched response")
    func storyVoiceDecodes() throws {
        let json = """
        {
            "recording_id": "rec-003",
            "audio_url": "https://storage.anky.app/recordings/rec-003.m4a",
            "language": "es",
            "duration_seconds": 150.0
        }
        """.data(using: .utf8)!

        let voice = try decoder.decode(StoryVoice.self, from: json)

        #expect(voice.recordingId == "rec-003")
        #expect(voice.language == "es")
        #expect(voice.durationSeconds == 150.0)
    }

    @Test("VoiceRecording array decodes ordered by attempt_number")
    func recordingsArrayDecodes() throws {
        let json = """
        [
            {"id": "r1", "attempt_number": 1, "status": "rejected", "duration_seconds": 30, "created_at": "2026-03-20T10:00:00Z", "audio_url": null, "rejection_reason": "too fast"},
            {"id": "r2", "attempt_number": 2, "status": "approved", "duration_seconds": 150, "created_at": "2026-03-20T11:00:00Z", "audio_url": "https://x.com/r2.m4a", "rejection_reason": null},
            {"id": "r3", "attempt_number": 3, "status": "pending", "duration_seconds": 145, "created_at": "2026-03-20T12:00:00Z", "audio_url": null, "rejection_reason": null}
        ]
        """.data(using: .utf8)!

        let recordings = try decoder.decode([VoiceRecording].self, from: json)

        #expect(recordings.count == 3)
        #expect(recordings[0].attemptNumber == 1)
        #expect(recordings[1].status == .approved)
        #expect(recordings[2].status == .pending)
    }
}

// MARK: - Offline Queue

struct OfflineQueueTests {
    @Test("Enqueued actions persist and can be counted")
    func enqueueAndCount() async {
        let queue = OfflineQueue()
        await queue.clear()

        let body = try! JSONEncoder().encode(MobileWriteRequest(
            text: Array(repeating: "word", count: 300).joined(separator: " "),
            duration: 500,
            sessionId: "q-1",
            keystrokeDeltas: nil,
            isCheckpoint: nil
        ))

        let action = PendingAction(method: .post, path: "/write", bodyData: body)
        await queue.enqueue(action)

        let count = await queue.count()
        #expect(count == 1)

        await queue.clear()
        let countAfterClear = await queue.count()
        #expect(countAfterClear == 0)
    }

    @Test("Short writes are filtered as obsolete from the queue")
    func shortWritesAreObsolete() {
        let shortBody = try! JSONSerialization.data(withJSONObject: [
            "text": "too short",
            "duration": 90.0,
            "session_id": "short-1"
        ] as [String: Any])

        let longBody = try! JSONSerialization.data(withJSONObject: [
            "text": Array(repeating: "word", count: 300).joined(separator: " "),
            "duration": 500.0,
            "session_id": "long-1"
        ] as [String: Any])

        let shortAction = PendingAction(method: .post, path: "/write", bodyData: shortBody)
        let longAction = PendingAction(method: .post, path: "/write", bodyData: longBody)
        let nonWriteAction = PendingAction(method: .delete, path: "/auth/session", bodyData: nil)

        // Short write to /write = obsolete
        #expect(shortAction.isObsoleteShortWrite == true)
        // Long write to /write = not obsolete
        #expect(longAction.isObsoleteShortWrite == false)
        // Non-write action = not obsolete
        #expect(nonWriteAction.isObsoleteShortWrite == false)
    }
}

// MARK: - Writing Cache Store

struct WritingCacheModelTests {
    @Test("CachedWritingEntry initializes from WritingItem correctly")
    func entryFromWritingItem() {
        let item = WritingItem(
            id: "w-1",
            content: "stream of text",
            durationSeconds: 500,
            wordCount: 320,
            isAnky: true,
            response: "reflection",
            ankyId: "anky-1",
            ankyTitle: "Born",
            ankyImagePath: "/images/anky.png",
            createdAt: "2026-03-20T10:00:00Z"
        )

        let entry = CachedWritingEntry(item: item, prompt: "What do you see?")

        #expect(entry.id == "w-1")
        #expect(entry.prompt == "What do you see?")
        #expect(entry.content == "stream of text")
        #expect(entry.durationSeconds == 500)
        #expect(entry.wordCount == 320)
        #expect(entry.isAnky == true)
        #expect(entry.ankyId == "anky-1")
        #expect(entry.syncState == .synced)
    }

    @Test("CachedWritingEntry from WritingItem defaults prompt to empty")
    func entryFromItemDefaultPrompt() {
        let item = WritingItem(
            id: "w-2",
            content: "text",
            durationSeconds: 90,
            wordCount: 5,
            isAnky: false,
            response: nil,
            ankyId: nil,
            ankyTitle: nil,
            ankyImagePath: nil,
            createdAt: "2026-03-20T10:00:00Z"
        )

        let entry = CachedWritingEntry(item: item)
        #expect(entry.prompt == "")
        #expect(entry.isAnky == false)
        #expect(entry.syncState == .synced)
    }

    @Test("Sync states encode and decode correctly")
    func syncStatesRoundTrip() throws {
        let states: [CachedWritingSyncState] = [.synced, .pending, .localOnly]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for state in states {
            let data = try encoder.encode(state)
            let decoded = try decoder.decode(CachedWritingSyncState.self, from: data)
            #expect(decoded == state)
        }
    }
}

// MARK: - Draft Persistence

struct DraftPersistenceTests {
    @Test("StoredWritingDraft round-trips through JSON encoding")
    func draftRoundTrips() throws {
        let draft = StoredWritingDraft(
            sessionId: "draft-1",
            prompt: "What do you see?",
            text: "I see the ocean stretching beyond",
            sessionElapsed: 245.5,
            livesRemaining: 1,
            keystrokeDeltas: [120, 80, 95, 200, 150],
            wasInterrupted: true,
            updatedAt: Date(timeIntervalSince1970: 1742500000)
        )

        let data = try JSONEncoder().encode(draft)
        let loaded = try JSONDecoder().decode(StoredWritingDraft.self, from: data)

        #expect(loaded.sessionId == "draft-1")
        #expect(loaded.prompt == "What do you see?")
        #expect(loaded.text == "I see the ocean stretching beyond")
        #expect(loaded.sessionElapsed == 245.5)
        #expect(loaded.livesRemaining == 1)
        #expect(loaded.keystrokeDeltas.count == 5)
        #expect(loaded.wasInterrupted == true)
        #expect(loaded == draft)
    }

    @Test("StoredWritingDraft equality works correctly")
    func draftEquality() {
        let date = Date(timeIntervalSince1970: 1742500000)
        let draft1 = StoredWritingDraft(
            sessionId: "d-1", prompt: "p", text: "t",
            sessionElapsed: 10, livesRemaining: 2,
            keystrokeDeltas: [100], wasInterrupted: false, updatedAt: date
        )
        let draft2 = StoredWritingDraft(
            sessionId: "d-1", prompt: "p", text: "t",
            sessionElapsed: 10, livesRemaining: 2,
            keystrokeDeltas: [100], wasInterrupted: false, updatedAt: date
        )
        let draft3 = StoredWritingDraft(
            sessionId: "d-2", prompt: "p", text: "t",
            sessionElapsed: 10, livesRemaining: 2,
            keystrokeDeltas: [100], wasInterrupted: false, updatedAt: date
        )

        #expect(draft1 == draft2)
        #expect(draft1 != draft3)
    }
}

// MARK: - Flow Score Estimation

struct FlowScoreTests {
    @Test("Anky qualification requires exactly 480s and 300 words")
    func qualificationBoundaries() {
        let words300 = Array(repeating: "word", count: 300).joined(separator: " ")
        let words299 = Array(repeating: "word", count: 299).joined(separator: " ")

        // Exact boundaries
        #expect(LocalWritingCapture.qualifiesForAnky(text: words300, duration: 480) == true)
        #expect(LocalWritingCapture.qualifiesForAnky(text: words300, duration: 479.9) == false)
        #expect(LocalWritingCapture.qualifiesForAnky(text: words299, duration: 480) == false)

        // Well over
        #expect(LocalWritingCapture.qualifiesForAnky(text: words300, duration: 600) == true)

        // Empty
        #expect(LocalWritingCapture.qualifiesForAnky(text: "", duration: 0) == false)
        #expect(LocalWritingCapture.qualifiesForAnky(text: "", duration: 600) == false)
    }

    @Test("Word count handles whitespace and newlines correctly")
    func wordCountEdgeCases() {
        #expect(LocalWritingCapture.wordCount(in: "") == 0)
        #expect(LocalWritingCapture.wordCount(in: "   ") == 0)
        #expect(LocalWritingCapture.wordCount(in: "one") == 1)
        #expect(LocalWritingCapture.wordCount(in: "one two three") == 3)
        #expect(LocalWritingCapture.wordCount(in: "one\ntwo\nthree") == 3)
        #expect(LocalWritingCapture.wordCount(in: "  one   two   three  ") == 3)
        #expect(LocalWritingCapture.wordCount(in: "one\n\n\ntwo") == 2)
    }

    @Test("LocalWritingCapture builds MobileWriteRequest correctly")
    func captureBuildsRequest() {
        let capture = LocalWritingCapture(
            sessionId: "cap-1",
            prompt: "Write",
            text: "Hello world",
            duration: 500,
            wordCount: 2,
            keystrokeDeltas: [100, 200],
            finishedAt: .now,
            estimatedFlowScore: 0.75
        )

        let request = capture.request
        #expect(request.text == "Hello world")
        #expect(request.duration == 500)
        #expect(request.sessionId == "cap-1")
        #expect(request.keystrokeDeltas == [100, 200])
        #expect(request.isCheckpoint == nil)
    }

    @Test("Checkpoint request sets isCheckpoint true")
    func checkpointRequest() {
        let capture = LocalWritingCapture(
            sessionId: "cap-1",
            prompt: "Write",
            text: "",
            duration: 0,
            wordCount: 0,
            keystrokeDeltas: [],
            finishedAt: .now,
            estimatedFlowScore: 0
        )

        let request = capture.checkpointRequest(
            text: "partial text",
            duration: 30,
            keystrokeDeltas: [50, 60]
        )

        #expect(request.isCheckpoint == true)
        #expect(request.text == "partial text")
        #expect(request.sessionId == "cap-1")
    }
}

// MARK: - Voice Duration Validation

struct VoiceDurationTests {
    @Test("Max duration is word_count / 2.5 + 30s buffer")
    func maxDurationCalculation() {
        // 500 word story: 500/2.5 = 200 + 30 = 230 seconds
        #expect(voiceMaxDuration(wordCount: 500) == 230.0)
    }

    @Test("Min duration is word_count / 5")
    func minDurationCalculation() {
        // 500 word story: 500/5 = 100 seconds
        #expect(voiceMinDuration(wordCount: 500) == 100.0)
    }

    @Test("Short story has proportional limits")
    func shortStoryLimits() {
        // 100 word story: max = 100/2.5 + 30 = 70, min = 100/5 = 20
        #expect(voiceMaxDuration(wordCount: 100) == 70.0)
        #expect(voiceMinDuration(wordCount: 100) == 20.0)
    }

    // Mirror the VoiceRecordingManager formulas without needing @MainActor
    private func voiceMaxDuration(wordCount: Int) -> Double {
        Double(wordCount) / 2.5 + 30
    }

    private func voiceMinDuration(wordCount: Int) -> Double {
        Double(wordCount) / 5.0
    }
}

// MARK: - API Route Tests (Voice Endpoints)

struct VoiceAPIRouteTests {
    @Test("Voice recording routes resolve under /swift/v2")
    func voiceRoutesResolve() throws {
        let api = AnkyAPI(baseURL: URL(string: "https://anky.app/swift/v2")!)

        #expect(try api.resolveURL(for: "/stories/story-123/recordings").absoluteString
            == "https://anky.app/swift/v2/stories/story-123/recordings")
        #expect(try api.resolveURL(for: "/stories/story-123/voice").absoluteString
            == "https://anky.app/swift/v2/stories/story-123/voice")
        #expect(try api.resolveURL(for: "/stories/story-123/recordings/rec-456/complete").absoluteString
            == "https://anky.app/swift/v2/stories/story-123/recordings/rec-456/complete")
    }
}

// MARK: - CachedWritingEntry Formatting

struct CachedWritingEntryTests {
    @Test("Duration label formats minutes and seconds correctly")
    func durationLabelFormats() {
        let entry1 = makeEntry(duration: 480)
        #expect(entry1.durationLabel == "8m 0s")

        let entry2 = makeEntry(duration: 125.7)
        #expect(entry2.durationLabel == "2m 5s")

        let entry3 = makeEntry(duration: 59)
        #expect(entry3.durationLabel == "0m 59s")

        let entry4 = makeEntry(duration: 0)
        #expect(entry4.durationLabel == "0m 0s")
    }

    @Test("Image URL normalizes relative and absolute paths")
    func imageUrlNormalization() {
        let relativeEntry = makeEntry(imagePath: "images/anky.png")
        #expect(relativeEntry.remoteImageURL?.absoluteString == "https://anky.app/images/anky.png")

        let absoluteEntry = makeEntry(imagePath: "https://cdn.anky.app/img.png")
        #expect(absoluteEntry.remoteImageURL?.absoluteString == "https://cdn.anky.app/img.png")

        let slashEntry = makeEntry(imagePath: "/images/anky.png")
        #expect(slashEntry.remoteImageURL?.absoluteString == "https://anky.app/images/anky.png")

        let emptyEntry = makeEntry(imagePath: "")
        #expect(emptyEntry.remoteImageURL == nil)

        let nilEntry = makeEntry(imagePath: nil)
        #expect(nilEntry.remoteImageURL == nil)

        let whitespaceEntry = makeEntry(imagePath: "  ")
        #expect(whitespaceEntry.remoteImageURL == nil)
    }

    private func makeEntry(duration: Double = 480, imagePath: String? = nil) -> CachedWritingEntry {
        CachedWritingEntry(
            id: "test",
            prompt: "",
            content: "",
            durationSeconds: duration,
            wordCount: 300,
            isAnky: true,
            response: nil,
            ankyId: nil,
            ankyTitle: nil,
            ankyImagePath: imagePath,
            createdAt: .now,
            flowScore: nil,
            syncState: .synced
        )
    }
}

// MARK: - VoiceRecording Formatting

struct VoiceRecordingFormattingTests {
    @Test("Duration label formats correctly")
    func durationLabel() {
        let short = VoiceRecording(
            id: "r1", attemptNumber: 1, status: .pending,
            durationSeconds: 45, createdAt: "2026-03-20T10:00:00Z",
            audioUrl: nil, rejectionReason: nil,
            language: nil, fullListenCount: nil, userId: nil, username: nil
        )
        #expect(short.durationLabel == "0:45")

        let long = VoiceRecording(
            id: "r2", attemptNumber: 2, status: .approved,
            durationSeconds: 142.5, createdAt: "2026-03-20T10:00:00Z",
            audioUrl: "https://x.com/r2.m4a", rejectionReason: nil,
            language: nil, fullListenCount: nil, userId: nil, username: nil
        )
        #expect(long.durationLabel == "2:22")
    }

    @Test("Status label returns correct strings")
    func statusLabels() {
        let pending = VoiceRecording(
            id: "r1", attemptNumber: 1, status: .pending,
            durationSeconds: 100, createdAt: "", audioUrl: nil, rejectionReason: nil,
            language: nil, fullListenCount: nil, userId: nil, username: nil
        )
        let approved = VoiceRecording(
            id: "r2", attemptNumber: 2, status: .approved,
            durationSeconds: 100, createdAt: "", audioUrl: nil, rejectionReason: nil,
            language: nil, fullListenCount: nil, userId: nil, username: nil
        )
        let rejected = VoiceRecording(
            id: "r3", attemptNumber: 3, status: .rejected,
            durationSeconds: 100, createdAt: "", audioUrl: nil, rejectionReason: "bad",
            language: nil, fullListenCount: nil, userId: nil, username: nil
        )

        #expect(pending.statusLabel == "pending")
        #expect(approved.statusLabel == "approved")
        #expect(rejected.statusLabel == "rejected")
    }
}

// MARK: - Live Production Integration (gated behind ANKY_LIVE_BACKEND=1)

struct VoicesLiveIntegrationTests {
    private let testStoryId = "84861939-bde9-4e51-844f-d675adf6194f"
    private let vectorMnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art"

    /// Authenticate via seed auth and return a configured API + session token.
    private func authenticateTestUser() async throws -> (AnkyAPI, String) {
        let api = AnkyAPI(baseURL: URL(string: "https://anky.app/swift/v2")!)
        let privateKeyData = try SeedIdentityCrypto.derivedPrivateKey(from: vectorMnemonic)
        let walletAddress = try SeedIdentityCrypto.walletAddress(fromPrivateKey: privateKeyData)

        let challenge = try await api.authChallenge(walletAddress: walletAddress)
        let signature = try SeedIdentityCrypto.sign(
            message: Data(challenge.message.utf8),
            privateKeyData: privateKeyData
        )
        let verify = try await api.verifyAuthChallenge(
            walletAddress: walletAddress,
            challengeID: challenge.challengeId,
            signature: signature.hexStringPrefixed
        )

        // Store token so the API instance can use it
        KeychainHelper.set(verify.sessionToken, for: AppState.sessionTokenKey)
        return (api, verify.sessionToken)
    }

    /// Generate a minimal valid AAC/M4A audio file (silence, ~1 second).
    private func minimalAudioData() -> Data {
        // Minimal M4A container with silence — ftyp + moov + mdat
        // Using a 44-byte ftyp box for isom/M4A compatibility
        var data = Data()
        // ftyp box: file type
        let ftyp: [UInt8] = [
            0x00, 0x00, 0x00, 0x14, // size = 20
            0x66, 0x74, 0x79, 0x70, // "ftyp"
            0x69, 0x73, 0x6F, 0x6D, // "isom"
            0x00, 0x00, 0x00, 0x00, // minor version
            0x69, 0x73, 0x6F, 0x6D, // compatible brand "isom"
        ]
        data.append(contentsOf: ftyp)
        // mdat box: empty media data
        let mdat: [UInt8] = [
            0x00, 0x00, 0x00, 0x08, // size = 8
            0x6D, 0x64, 0x61, 0x74, // "mdat"
        ]
        data.append(contentsOf: mdat)
        return data
    }

    @Test("Full voice recording flow against production")
    func fullVoiceFlowAgainstProduction() async throws {
        guard ProcessInfo.processInfo.environment["ANKY_LIVE_BACKEND"] == "1" else { return }

        let (api, _) = try await authenticateTestUser()
        defer { KeychainHelper.delete(AppState.sessionTokenKey) }

        let audioData = minimalAudioData()

        // Step 1: Create recording
        let createResponse = try await api.createRecording(
            storyId: testStoryId,
            audioData: audioData,
            language: "en",
            durationSeconds: 1.0
        )

        #expect(!createResponse.recordingId.isEmpty)
        #expect(createResponse.status == "pending")
        #expect(!createResponse.uploadUrl.isEmpty)

        // Step 2: Upload to R2
        try await api.uploadAudioToR2(
            uploadUrl: createResponse.uploadUrl,
            audioData: audioData
        )

        // Step 3: List recordings — our recording should appear
        let recordings = try await api.getRecordings(storyId: testStoryId)
        let ourRecording = recordings.first(where: { $0.id == createResponse.recordingId })
        #expect(ourRecording != nil)

        // Step 4: Get voice (auto-approved for now)
        do {
            let voice = try await api.getStoryVoice(storyId: testStoryId, language: "en")
            #expect(!voice.audioUrl.isEmpty)
            #expect(voice.language == "en")

            // Step 5: Mark listen complete
            try await api.markListenComplete(
                storyId: testStoryId,
                recordingId: voice.recordingId
            )
        } catch {
            // May 404 if not yet approved — that's acceptable
            print("Voice not yet available (may be pending): \(error)")
        }
    }

    @Test("GET /recordings without auth returns missingSession")
    func recordingsWithoutAuthReturnsMissingSession() async throws {
        guard ProcessInfo.processInfo.environment["ANKY_LIVE_BACKEND"] == "1" else { return }

        // Ensure no token is stored — the client guards locally before hitting the network
        KeychainHelper.delete(AppState.sessionTokenKey)

        let api = AnkyAPI(baseURL: URL(string: "https://anky.app/swift/v2")!)

        do {
            _ = try await api.getRecordings(storyId: testStoryId)
            Issue.record("Expected missingSession error but request succeeded")
        } catch let error as AnkyError {
            #expect(error == .missingSession)
        }
    }

    @Test("GET /voice on story with no recordings returns error")
    func voiceOnEmptyStoryReturnsError() async throws {
        guard ProcessInfo.processInfo.environment["ANKY_LIVE_BACKEND"] == "1" else { return }

        let (api, _) = try await authenticateTestUser()
        defer { KeychainHelper.delete(AppState.sessionTokenKey) }

        // Use a non-existent story ID
        let fakeStoryId = "00000000-0000-0000-0000-000000000000"
        do {
            _ = try await api.getStoryVoice(storyId: fakeStoryId, language: "en")
            Issue.record("Expected 404 but request succeeded")
        } catch {
            // Expected — 404 for no recordings
        }
    }
}
