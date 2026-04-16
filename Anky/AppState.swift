//
//  AppState.swift
//  Anky
//

import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    enum Route {
        case booting
        case welcome
        case recoveryImport
        case locked
        case unlocked
    }

    enum AuthStatus {
        case checking
        case signedOut
        case signedIn
    }

    enum Tab: Int, CaseIterable {
        case stories
        case write
        case you

        var label: String {
            switch self {
            case .stories: return "historias"
            case .write: return "anky"
            case .you: return "tú"
            }
        }

        var icon: String {
            switch self {
            case .stories: return "book.fill"
            case .write: return "circles.hexagongrid"
            case .you: return "person.fill"
            }
        }
    }

    enum ActiveExperience {
        case writing
    }

    static let sessionTokenKey = "anky_session_token"
    private static let unlockStateKey = "anky.has_unlocked_full_experience"
    private static let welcomeStateKey = "anky.has_completed_welcome"
    private static let mirrorStateKey = "anky.mirror_state"
    private static let totalCompletedSessionsKey = "anky.total_completed_sessions"
    private static let hasMintedFirstNFTKey = "anky.has_minted_first_nft"
    private static let firstSessionTimestampKey = "anky.first_session_timestamp"

    @Published var route: Route = .booting
    @Published var authStatus: AuthStatus = .checking
    @Published var user: UserProfile?
    @Published var currentTab: Tab = .write
    @Published var activeExperience: ActiveExperience?
    @Published var prompt: String = PromptLibrary.currentPrompt()
    /// Canonical local-first archive state.
    @Published private(set) var localArchiveRecords: [LocalArchiveRecord]
    /// Legacy UI projection kept while profile/history surfaces still read `CachedWritingEntry`.
    @Published var writingHistory: [CachedWritingEntry]
    @Published var isOfflineMode = false
    @Published var authError: String?
    @Published var syncMessage: String?
    @Published var didBootstrap = false
    @Published var pendingMnemonic: String?
    @Published var hasLocalIdentity = false
    @Published var hasBackedUpPhrase = false
    @Published var hasCompletedWelcome = UserDefaults.standard.bool(forKey: welcomeStateKey)
    @Published var hasUnlockedFullExperience = UserDefaults.standard.bool(forKey: unlockStateKey)
    @Published var hasInProgressWriting = WritingSessionStore.hasDraft() || WritingSessionStore.hasRecoverableLiveSession()
    @Published var deepLinkPrompt: String?
    @Published var qrSealChallenge: QRSealChallenge?
    @Published var sharedAnkyLink: SharedAnkyLink?
    @Published var pendingNowSlug: String?

    // Mirror architecture
    @Published var mirrorState: MirrorState = {
        let raw = UserDefaults.standard.integer(forKey: mirrorStateKey)
        return MirrorState(rawValue: raw) ?? .virgin
    }()
    @Published var kingdom: Kingdom = .primordia
    @Published var totalCompletedSessions: Int = UserDefaults.standard.integer(forKey: totalCompletedSessionsKey)
    @Published var hasMintedFirstNFT: Bool = UserDefaults.standard.bool(forKey: hasMintedFirstNFTKey)
    @Published var firstSessionTimestamp: Date? = {
        let ti = UserDefaults.standard.double(forKey: firstSessionTimestampKey)
        return ti > 0 ? Date(timeIntervalSince1970: ti) : nil
    }()

    init() {
        let initialArchiveRecords = LocalArchiveStore.load()
        self.localArchiveRecords = initialArchiveRecords
        self.writingHistory = initialArchiveRecords.map(\.legacyCachedWritingEntry)
    }

    func setMirrorState(_ state: MirrorState) {
        mirrorState = state
        UserDefaults.standard.set(state.rawValue, forKey: Self.mirrorStateKey)
    }

    func deriveKingdom() {
        if let address = try? SeedIdentityManager.shared.walletAddress() {
            kingdom = Kingdom.from(walletAddress: address)
        }
    }

    func recordFirstSession(timestamp: Date) {
        firstSessionTimestamp = timestamp
        UserDefaults.standard.set(timestamp.timeIntervalSince1970, forKey: Self.firstSessionTimestampKey)
    }

    func incrementCompletedSessions() {
        totalCompletedSessions += 1
        UserDefaults.standard.set(totalCompletedSessions, forKey: Self.totalCompletedSessionsKey)
    }

    @Published var mirrorId: String? = UserDefaults.standard.string(forKey: "anky.mirror_id")
    @Published var mirrorItems: [KingdomItem]?
    @Published var mirrorImageUrl: String?

    func markFirstMintComplete() {
        hasMintedFirstNFT = true
        UserDefaults.standard.set(true, forKey: Self.hasMintedFirstNFTKey)
    }

    func saveMirrorMint(response: MirrorMintResponse) {
        mirrorId = response.mirrorId
        mirrorItems = response.items?.items
        mirrorImageUrl = response.imageUrl
        if let id = response.mirrorId {
            UserDefaults.standard.set(id, forKey: "anky.mirror_id")
        }
        if let kingdomName = response.kingdom, let k = Kingdom.from(name: kingdomName) {
            kingdom = k
        }
        markFirstMintComplete()
    }

    var isAuthenticated: Bool { authStatus == .signedIn }

    /// Whether the user has completed a writing session today (UTC)
    var hasWrittenToday: Bool {
        let now = Date()
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return localArchiveRecords.contains { record in
            utc.isDate(record.createdAt, inSameDayAs: now)
        }
    }

    /// Whether the user has completed an anky-qualifying session today (UTC)
    var hasWrittenAnkyToday: Bool {
        let now = Date()
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return localArchiveRecords.contains { record in
            (record.isAnky ?? record.sessionBundle.qualifiesForCanonicalAnky)
                && utc.isDate(record.createdAt, inSameDayAs: now)
        }
    }

    /// Today's writing entry (if any), UTC-based
    var todaysWriting: CachedWritingEntry? {
        let now = Date()
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return localArchiveRecords.first { record in
            utc.isDate(record.createdAt, inSameDayAs: now)
        }?.legacyCachedWritingEntry
    }

    var canonicalArchiveAnkys: [LocalArchiveRecord] {
        localArchiveRecords.filter { record in
            record.isAnky ?? record.sessionBundle.qualifiesForCanonicalAnky
        }
    }

    var cloudHistory: [CachedWritingEntry] {
        localArchiveRecords
            .filter { $0.sessionBundle.syncStatus == .synced || $0.sessionBundle.syncStatus == .legacyRemoteProjection }
            .map(\.legacyCachedWritingEntry)
    }

    var pendingPersistedWrites: [CachedWritingEntry] {
        pendingArchiveRecords.map(\.legacyCachedWritingEntry)
    }

    var pendingArchiveRecords: [LocalArchiveRecord] {
        localArchiveRecords.filter {
            $0.sessionBundle.qualifiesForCanonicalAnky
                && ($0.sessionBundle.syncStatus == .pending || $0.needsCanonicalProcessorReconciliation)
        }
    }

    func archiveRecord(for sessionId: String) -> LocalArchiveRecord? {
        localArchiveRecords.first { $0.id == sessionId }
    }

    func archiveRecord(forSessionHash sessionHash: String) -> LocalArchiveRecord? {
        localArchiveRecords.first { $0.sessionBundle.sessionHash == sessionHash }
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        prompt = PromptLibrary.currentPrompt()
        replaceArchiveRecords(LocalArchiveStore.migrateLegacyShortPendingWrites())
        hasInProgressWriting = WritingSessionStore.hasDraft() || WritingSessionStore.hasRecoverableLiveSession()
        hasUnlockedFullExperience = UserDefaults.standard.bool(forKey: Self.unlockStateKey)
        hasCompletedWelcome = UserDefaults.standard.bool(forKey: Self.welcomeStateKey)

        // Reload mirror state
        let savedMirrorState = UserDefaults.standard.integer(forKey: Self.mirrorStateKey)
        mirrorState = MirrorState(rawValue: savedMirrorState) ?? .virgin

        // Ensure encryption keypair exists (for session sealing)
        _ = try? AnkyProtocol.ensureKeypair()

        let identityStatus = SeedIdentityManager.shared.status()
        if !identityStatus.hasIdentity {
            do {
                let snapshot = try SeedIdentityManager.shared.generateIdentity()
                hasLocalIdentity = true
                hasBackedUpPhrase = false
                pendingMnemonic = snapshot.mnemonic
                hasCompletedWelcome = false
                UserDefaults.standard.set(false, forKey: Self.welcomeStateKey)
                setMirrorState(.virgin)
                route = .welcome
                authStatus = .signedOut
            } catch {
                authError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                route = .recoveryImport
            }
            return
        }

        hasLocalIdentity = true
        deriveKingdom()
        hasCompletedWelcome = hasCompletedWelcome || identityStatus.hasCompletedBackup
        UserDefaults.standard.set(hasCompletedWelcome, forKey: Self.welcomeStateKey)
        hasBackedUpPhrase = hasCompletedWelcome || identityStatus.hasCompletedBackup
        pendingMnemonic = identityStatus.pendingMnemonic

        // Route: unlocked if first anky persisted, otherwise welcome/onboarding
        if mirrorState.rawValue >= MirrorState.firstMintComplete.rawValue && hasUnlockedFullExperience {
            route = .unlocked
        } else {
            // First-run onboarding (or returning locked user who hasn't completed first anky)
            route = .welcome
        }

        guard mirrorState.rawValue >= MirrorState.firstMintComplete.rawValue || hasCompletedWelcome || mirrorState.rawValue >= MirrorState.seedConfirmed.rawValue else {
            // Start silent auth in background for onboarding users
            Task { await refreshAuthenticatedState() }
            return
        }

        await refreshAuthenticatedState()
    }

    func completeWelcome() async {
        SeedIdentityManager.shared.markBackupCompleted()
        hasBackedUpPhrase = true
        hasCompletedWelcome = true
        UserDefaults.standard.set(true, forKey: Self.welcomeStateKey)
        pendingMnemonic = nil
        route = hasUnlockedFullExperience ? .unlocked : .locked
        _ = await refreshAuthenticatedState(forceFreshSession: true)
    }

    func showRecoveryImport() {
        route = .recoveryImport
    }

    func cancelRecoveryImport() {
        route = hasUnlockedFullExperience ? .unlocked : .welcome
    }

    func importRecoveryPhrase(_ phrase: String) async -> Bool {
        authError = nil
        do {
            _ = try SeedIdentityManager.shared.importIdentity(from: phrase)
            hasLocalIdentity = true
            hasBackedUpPhrase = true
            hasCompletedWelcome = true
            UserDefaults.standard.set(true, forKey: Self.welcomeStateKey)
            pendingMnemonic = nil
            route = hasUnlockedFullExperience ? .unlocked : .locked
            return await refreshAuthenticatedState(forceFreshSession: true)
        } catch {
            authError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    @discardableResult
    func refreshAuthenticatedState(forceFreshSession: Bool = false) async -> Bool {
        guard hasLocalIdentity else {
            authStatus = .signedOut
            user = nil
            return false
        }

        authStatus = .checking
        authError = nil

        if !forceFreshSession, KeychainHelper.get(Self.sessionTokenKey) != nil {
            do {
                let profile = try await AnkyAPI.shared.me()
                consumeAuthenticatedProfile(profile)
                await postAuthRefresh()
                return true
            } catch let error as AnkyError {
                switch error {
                case .unauthorized, .missingSession:
                    KeychainHelper.delete(Self.sessionTokenKey)
                case .transport:
                    authStatus = .signedOut
                    isOfflineMode = true
                    syncMessage = "offline"
                    return false
                default:
                    break
                }
            } catch {
                authStatus = .signedOut
                return false
            }
        }

        do {
            let profile = try await SeedAuthService.shared.authenticate(using: SeedIdentityManager.shared)
            consumeAuthenticatedProfile(profile)
            await postAuthRefresh()
            return true
        } catch let error as AnkyError where error.isConnectivityIssue {
            authStatus = .signedOut
            isOfflineMode = true
            syncMessage = "offline"
            return false
        } catch {
            authStatus = .signedOut
            authError = "Identity could not be restored right now."
            return false
        }
    }

    func ensureAuthenticatedForWrite() async -> Bool {
        if isAuthenticated { return true }
        return await refreshAuthenticatedState(forceFreshSession: true)
    }

    func applyPersistedAnkySuccess(
        capture: LocalWritingCapture,
        response: MobileWriteResponse,
        shouldRouteToUnlocked: Bool = true,
        shouldSwitchToStories: Bool = true
    ) async {
        recordWriting(capture, response: response, syncState: .synced)
        markUnlocked()
        await refreshUserProfile()
        await refreshWritings()
        // Only auto-route to unlocked if not in onboarding (onboarding manages its own transitions)
        if shouldRouteToUnlocked, route != .welcome {
            if shouldSwitchToStories {
                currentTab = .stories
            }
            route = .unlocked
        }
    }

    func storeCanonicalAcceptedSubmission(
        for sessionId: String,
        backendAnkyId: String,
        shouldRouteToUnlocked: Bool = false,
        shouldSwitchToStories: Bool = false
    ) async {
        replaceArchiveRecords(
            LocalArchiveStore.updateAcceptedSubmission(
                for: sessionId,
                backendAnkyId: backendAnkyId
            )
        )
        markUnlocked()
        await refreshUserProfile()
        if shouldRouteToUnlocked, route != .welcome {
            if shouldSwitchToStories {
                currentTab = .stories
            }
            route = .unlocked
        }
    }

    func clearSession() async {
        DeviceTokenManager.shared.unregister()
        await SeedAuthService.shared.logout()
        user = nil
        authStatus = .signedOut
        isOfflineMode = false
        syncMessage = nil
    }

    func rebootIdentity() async {
        DeviceTokenManager.shared.unregister()
        await clearSession()
        SeedIdentityManager.shared.wipeIdentity()
        AnkyProtocol.wipeKeypair()
        SealedSessionStore.clear()
        WritingCacheStore.clear()
        WritingSessionStore.clearDraft()
        WritingSessionStore.clearLiveSession()
        PendingMintStore.clear()
        ArweaveStore.clear()
        AnkyNameStore.clear()
        await OfflineQueue.shared.clear()

        user = nil
        prompt = PromptLibrary.currentPrompt()
        localArchiveRecords = []
        writingHistory = []
        currentTab = .write
        activeExperience = nil
        authError = nil
        syncMessage = nil
        isOfflineMode = false
        hasUnlockedFullExperience = false
        hasCompletedWelcome = false
        hasBackedUpPhrase = false
        UserDefaults.standard.set(false, forKey: Self.unlockStateKey)
        UserDefaults.standard.set(false, forKey: Self.welcomeStateKey)

        // Reset mirror state
        setMirrorState(.virgin)
        kingdom = .primordia
        totalCompletedSessions = 0
        hasMintedFirstNFT = false
        firstSessionTimestamp = nil
        UserDefaults.standard.set(0, forKey: Self.totalCompletedSessionsKey)
        UserDefaults.standard.set(false, forKey: Self.hasMintedFirstNFTKey)
        UserDefaults.standard.removeObject(forKey: Self.firstSessionTimestampKey)

        // Clear chat history
        ChatStore.shared.clearAll()

        do {
            let snapshot = try SeedIdentityManager.shared.generateIdentity()
            hasLocalIdentity = true
            pendingMnemonic = snapshot.mnemonic
            route = .welcome
        } catch {
            hasLocalIdentity = false
            hasBackedUpPhrase = false
            hasCompletedWelcome = false
            pendingMnemonic = nil
            route = .recoveryImport
            authError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func refreshWritings() async {
        guard isAuthenticated else { return }

        do {
            let items = try await AnkyAPI.shared.writings()
            replaceArchiveRecords(LocalArchiveStore.mergeRemote(items))
            await refreshCanonicalArchiveReadback()
        } catch let error as AnkyError where error.isConnectivityIssue {
            isOfflineMode = true
        } catch {
            syncMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func refreshUserProfile() async {
        guard isAuthenticated else { return }

        do {
            user = try await AnkyAPI.shared.me()
            isOfflineMode = false
        } catch let error as AnkyError where error.isConnectivityIssue {
            isOfflineMode = true
        } catch {
            syncMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func recordWriting(
        _ capture: LocalWritingCapture,
        response: MobileWriteResponse?,
        syncState: CachedWritingSyncState,
        reflectionText: String? = nil
    ) {
        let isPersistedAnky = response?.persisted == true
            && response?.isAnky == true
            && capture.qualifiesForAnky
        let isPendingAnky = syncState == .pending && capture.qualifiesForAnky
        let canonicalSyncStatus: AnkySessionBundle.SyncStatus = {
            if isPersistedAnky {
                return .synced
            }
            if isPendingAnky {
                return .pending
            }
            return syncState.canonicalSyncStatus
        }()

        let archiveRecord = capture.localArchiveRecord(
            syncStatus: canonicalSyncStatus,
            backendAnkyId: response?.ankyId,
            reflection: reflectionText ?? response?.ankyResponse
        )
        .updating(flowScore: response?.flowScore ?? capture.estimatedFlowScore)
        .reconcilingCanonicalSyncStatus(updatedAt: .now)

        replaceArchiveRecords(LocalArchiveStore.prepend(archiveRecord))
        prompt = PromptLibrary.advancePrompt(seed: capture.text)
        hasInProgressWriting = WritingSessionStore.hasDraft() || WritingSessionStore.hasRecoverableLiveSession()
    }

    func storeReflection(_ reflection: String, for sessionId: String) {
        replaceArchiveRecords(LocalArchiveStore.updateResponse(for: sessionId, response: reflection))
    }

    func storeGeneratedArtifacts(
        for sessionId: String,
        reflection: String? = nil,
        ankyTitle: String? = nil,
        ankyImagePath: String? = nil
    ) {
        replaceArchiveRecords(LocalArchiveStore.updateGeneratedArtifacts(
            for: sessionId,
            reflection: reflection,
            ankyTitle: ankyTitle,
            ankyImagePath: ankyImagePath
        ))
    }

    func storeRetryArtifacts(
        for sessionId: String,
        ankySessionString: String? = nil,
        ankyFilePath: String? = nil,
        sessionHash: String? = nil
    ) {
        replaceArchiveRecords(LocalArchiveStore.updateRetryArtifacts(
            for: sessionId,
            ankySessionString: ankySessionString,
            ankyFilePath: ankyFilePath,
            sessionHash: sessionHash
        ))
    }

    func updateWritingSyncState(for sessionId: String, syncState: CachedWritingSyncState) {
        replaceArchiveRecords(
            LocalArchiveStore.updateSyncStatus(
                for: sessionId,
                syncStatus: syncState.canonicalSyncStatus
            )
        )
    }

    func applyCanonicalProcessorStatus(
        _ response: CanonicalProcessorStatusResponse,
        sessionId: String? = nil,
        sessionHash: String
    ) {
        replaceArchiveRecords(
            LocalArchiveStore.applyCanonicalProcessorStatus(
                for: sessionId,
                sessionHash: sessionHash,
                response: response
            )
        )
    }

    func applyCanonicalProofReadback(
        _ response: CanonicalProofResponse,
        sessionId: String? = nil,
        sessionHash: String
    ) {
        replaceArchiveRecords(
            LocalArchiveStore.applyCanonicalProofReadback(
                for: sessionId,
                sessionHash: sessionHash,
                response: response
            )
        )
    }

    func reconcileCanonicalArchiveRecord(
        sessionId: String,
        pollUntilSettled: Bool = false,
        maxAttempts: Int = 12
    ) async -> LocalArchiveRecord? {
        guard let initialRecord = archiveRecord(for: sessionId) else {
            return nil
        }

        var latestRecord: LocalArchiveRecord? = initialRecord
        var retryDelay: UInt64 = 1_500_000_000
        let attempts = max(maxAttempts, 1)

        for attempt in 0..<attempts {
            if let currentRecord = latestRecord {
                latestRecord = await refreshCanonicalArchiveRecord(currentRecord)
            }

            guard pollUntilSettled else {
                return latestRecord
            }

            if latestRecord?.needsCanonicalProcessorReconciliation != true {
                return latestRecord
            }

            if attempt < attempts - 1 {
                try? await Task.sleep(nanoseconds: retryDelay)
                retryDelay = min(retryDelay * 2, 8_000_000_000)
                latestRecord = archiveRecord(for: sessionId)
            }
        }

        return latestRecord
    }

    func hydrateCanonicalArchiveRecordIfAvailable(sessionId: String) async -> LocalArchiveRecord? {
        guard let record = archiveRecord(for: sessionId),
              let sessionHash = record.sessionBundle.sessionHash,
              !sessionHash.isEmpty else {
            return nil
        }

        do {
            let snapshot = try await AnkyAPI.shared.getCanonicalSessionSnapshot(sessionHash: sessionHash)
            applyCanonicalProcessorStatus(snapshot, sessionId: record.id, sessionHash: sessionHash)

            if let proof = try? await AnkyAPI.shared.getCanonicalSessionProof(sessionHash: sessionHash) {
                applyCanonicalProofReadback(proof, sessionId: record.id, sessionHash: sessionHash)
            }

            return archiveRecord(for: record.id)
        } catch {
            return nil
        }
    }

    func queueWrite(_ capture: LocalWritingCapture) async {
        guard let bodyData = try? JSONEncoder().encode(capture.request) else { return }
        let action = PendingAction(method: .post, path: "/write", bodyData: bodyData)
        await OfflineQueue.shared.enqueue(action)
        syncMessage = "saved locally · sync when online"
    }

    func presentQRSealChallenge(token: String) {
        qrSealChallenge = QRSealChallenge(token: token)
    }

    func dismissQRSealChallenge() {
        qrSealChallenge = nil
    }

    func presentSharedAnky(id: String) {
        sharedAnkyLink = SharedAnkyLink(id: id)
    }

    func dismissSharedAnky() {
        sharedAnkyLink = nil
    }

    private func consumeAuthenticatedProfile(_ profile: UserProfile) {
        user = profile
        authStatus = .signedIn
        isOfflineMode = false
        syncMessage = nil
        if profile.totalAnkys > 0 {
            markUnlocked()
        }
    }

    private func postAuthRefresh() async {
        await refreshWritings()
        await UserSettings.shared.syncFromServer()
        let processed = await OfflineQueue.shared.processQueue(using: AnkyAPI.shared)
        if processed > 0 {
            syncMessage = "\(processed) pending sync\(processed == 1 ? "" : "s") delivered"
            await refreshUserProfile()
            await refreshWritings()
        }
        let pendingAnkyRetries = await PendingAnkyRetryService.retryPendingEntries(appState: self)
        if pendingAnkyRetries.syncedCount > 0 {
            print("[PendingAnkyRetry] Retried \(pendingAnkyRetries.syncedCount) pending anky submit(s)")
        }
        if pendingAnkyRetries.failedCount > 0 {
            print("[PendingAnkyRetry] Failed \(pendingAnkyRetries.failedCount) pending anky retry attempt(s)")
        }
        // Retry any sealed sessions that failed to reach the enclave
        let sealedRetries = await SealedSessionStore.retryPending(using: AnkyAPI.shared)
        if sealedRetries > 0 {
            print("[AnkyProtocol] Retried \(sealedRetries) sealed session(s)")
        }
        // Retry pending cNFT mints
        let mintRetries = await PendingMintStore.retryPending(appState: self)
        if mintRetries > 0 {
            print("[PendingMintStore] Retried \(mintRetries) mint(s)")
        }
        // Retry pending Arweave uploads
        let arweaveRetries = await ArweaveStore.retryPending()
        if arweaveRetries > 0 {
            print("[ArweaveStore] Retried \(arweaveRetries) upload(s)")
        }
    }

    /// Public variant for mirror dissolve view to call
    func markUnlockedPublic() {
        markUnlocked()
    }

    private func replaceArchiveRecords(_ records: [LocalArchiveRecord]) {
        localArchiveRecords = records
        writingHistory = records.map(\.legacyCachedWritingEntry)
    }

    private func refreshCanonicalArchiveReadback() async {
        let recordsToRefresh = localArchiveRecords.filter(\.needsCanonicalProcessorReconciliation)
        for record in recordsToRefresh {
            _ = await refreshCanonicalArchiveRecord(record)
        }
    }

    private func refreshCanonicalArchiveRecord(_ record: LocalArchiveRecord) async -> LocalArchiveRecord? {
        guard let sessionHash = record.sessionBundle.sessionHash,
              !sessionHash.isEmpty else {
            return nil
        }

        do {
            let snapshot = try await AnkyAPI.shared.getCanonicalSessionSnapshot(sessionHash: sessionHash)
            applyCanonicalProcessorStatus(snapshot, sessionId: record.id, sessionHash: sessionHash)

            if let proof = try? await AnkyAPI.shared.getCanonicalSessionProof(sessionHash: sessionHash) {
                applyCanonicalProofReadback(proof, sessionId: record.id, sessionHash: sessionHash)
            }

            return archiveRecord(for: record.id)
        } catch let error as AnkyError where error.isConnectivityIssue {
            return archiveRecord(for: record.id)
        } catch {
            return archiveRecord(for: record.id)
        }
    }

    private func markUnlocked() {
        if !hasUnlockedFullExperience {
            hasUnlockedFullExperience = true
            UserDefaults.standard.set(true, forKey: Self.unlockStateKey)
        }
    }
}
