//
//  AppState.swift
//  Anky
//

import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    enum Route {
        case booting
        case backupCeremony
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
        case now
        case ankys
        case seed

        var label: String {
            switch self {
            case .now: return "Now"
            case .ankys: return "Ankys"
            case .seed: return "Seed"
            }
        }

        var icon: String {
            switch self {
            case .now: return "pencil.and.scribble"
            case .ankys: return "square.stack.3d.down.forward"
            case .seed: return "key.horizontal"
            }
        }
    }

    enum ActiveExperience {
        case writing
        case meditation
        case breathwork
    }

    static let sessionTokenKey = "anky_session_token"
    private static let unlockStateKey = "anky.has_unlocked_full_experience"

    var route: Route = .booting
    var authStatus: AuthStatus = .checking
    var user: UserProfile?
    var currentTab: Tab = .now
    var activeExperience: ActiveExperience?
    var prompt: String = PromptLibrary.currentPrompt()
    var writingHistory: [CachedWritingEntry] = WritingCacheStore.load()
    var isOfflineMode = false
    var authError: String?
    var syncMessage: String?
    var didBootstrap = false
    var pendingMnemonic: String?
    var hasLocalIdentity = false
    var hasBackedUpPhrase = false
    var hasUnlockedFullExperience = UserDefaults.standard.bool(forKey: unlockStateKey)
    var hasInProgressWriting = WritingSessionStore.hasDraft()

    var isAuthenticated: Bool { authStatus == .signedIn }

    var cloudHistory: [CachedWritingEntry] {
        writingHistory.filter { $0.syncState == .synced }
    }

    var pendingPersistedWrites: [CachedWritingEntry] {
        writingHistory.filter { $0.syncState == .pending && $0.isAnky }
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        prompt = PromptLibrary.currentPrompt()
        writingHistory = WritingCacheStore.migrateLegacyShortPendingWrites()
        hasInProgressWriting = WritingSessionStore.hasDraft()
        hasUnlockedFullExperience = UserDefaults.standard.bool(forKey: Self.unlockStateKey)

        let identityStatus = SeedIdentityManager.shared.status()
        if !identityStatus.hasIdentity {
            do {
                let snapshot = try SeedIdentityManager.shared.generateIdentity()
                hasLocalIdentity = true
                hasBackedUpPhrase = false
                pendingMnemonic = snapshot.mnemonic
                route = .backupCeremony
                authStatus = .signedOut
            } catch {
                authError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                route = .recoveryImport
            }
            return
        }

        hasLocalIdentity = true
        hasBackedUpPhrase = identityStatus.hasCompletedBackup
        pendingMnemonic = identityStatus.pendingMnemonic
        route = (!hasBackedUpPhrase && pendingMnemonic != nil) ? .backupCeremony : (hasUnlockedFullExperience ? .unlocked : .locked)
        await refreshAuthenticatedState()
    }

    func completeBackupCeremony() async {
        SeedIdentityManager.shared.markBackupCompleted()
        hasBackedUpPhrase = true
        pendingMnemonic = nil
        route = hasUnlockedFullExperience ? .unlocked : .locked
        _ = await refreshAuthenticatedState(forceFreshSession: true)
    }

    func showRecoveryImport() {
        route = .recoveryImport
    }

    func cancelRecoveryImport() {
        route = (!hasBackedUpPhrase && pendingMnemonic != nil) ? .backupCeremony : (hasUnlockedFullExperience ? .unlocked : .locked)
    }

    func importRecoveryPhrase(_ phrase: String) async -> Bool {
        authError = nil
        do {
            _ = try SeedIdentityManager.shared.importIdentity(from: phrase)
            hasLocalIdentity = true
            hasBackedUpPhrase = true
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

    func applyPersistedAnkySuccess(capture: LocalWritingCapture, response: MobileWriteResponse) async {
        recordWriting(capture, response: response, syncState: .synced)
        markUnlocked()
        await refreshUserProfile()
        await refreshWritings()
        currentTab = .ankys
        route = .unlocked
    }

    func clearSession() async {
        await SeedAuthService.shared.logout()
        user = nil
        authStatus = .signedOut
        isOfflineMode = false
        syncMessage = nil
    }

    func rebootIdentity() async {
        await clearSession()
        SeedIdentityManager.shared.wipeIdentity()
        WritingCacheStore.clear()
        WritingSessionStore.clearDraft()
        await OfflineQueue.shared.clear()

        user = nil
        prompt = PromptLibrary.currentPrompt()
        writingHistory = []
        currentTab = .now
        activeExperience = nil
        authError = nil
        syncMessage = nil
        isOfflineMode = false
        hasUnlockedFullExperience = false
        UserDefaults.standard.set(false, forKey: Self.unlockStateKey)

        do {
            let snapshot = try SeedIdentityManager.shared.generateIdentity()
            hasLocalIdentity = true
            hasBackedUpPhrase = false
            pendingMnemonic = snapshot.mnemonic
            route = .backupCeremony
        } catch {
            hasLocalIdentity = false
            hasBackedUpPhrase = false
            pendingMnemonic = nil
            route = .recoveryImport
            authError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func refreshWritings() async {
        guard isAuthenticated else { return }

        do {
            let items = try await AnkyAPI.shared.writings()
            writingHistory = WritingCacheStore.mergeRemote(items)
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
        syncState: CachedWritingSyncState
    ) {
        let isPersistedAnky = response?.persisted == true && response?.isAnky == true
        let isPendingAnky = syncState == .pending && capture.qualifiesForAnky
        let isAnky = isPersistedAnky || isPendingAnky
        let entry = CachedWritingEntry(
            id: capture.sessionId,
            prompt: capture.prompt,
            content: capture.text,
            durationSeconds: capture.duration,
            wordCount: response?.wordCount ?? capture.wordCount,
            isAnky: isAnky,
            response: response?.response,
            ankyId: response?.ankyId,
            ankyTitle: isPersistedAnky ? "An anky was born." : nil,
            ankyImagePath: nil,
            createdAt: capture.finishedAt,
            flowScore: response?.flowScore ?? capture.estimatedFlowScore,
            syncState: syncState
        )

        writingHistory = WritingCacheStore.prepend(entry)
        prompt = PromptLibrary.advancePrompt(seed: capture.text)
        hasInProgressWriting = WritingSessionStore.hasDraft()
    }

    func queueWrite(_ capture: LocalWritingCapture) async {
        guard let bodyData = try? JSONEncoder().encode(capture.request) else { return }
        let action = PendingAction(method: .post, path: "/write", bodyData: bodyData)
        await OfflineQueue.shared.enqueue(action)
        syncMessage = "saved locally · sync when online"
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
        let processed = await OfflineQueue.shared.processQueue(using: AnkyAPI.shared)
        if processed > 0 {
            syncMessage = "\(processed) pending sync\(processed == 1 ? "" : "s") delivered"
            await refreshUserProfile()
            await refreshWritings()
        }
    }

    private func markUnlocked() {
        if !hasUnlockedFullExperience {
            hasUnlockedFullExperience = true
            UserDefaults.standard.set(true, forKey: Self.unlockStateKey)
        }

        if route != .backupCeremony && route != .recoveryImport {
            route = .unlocked
        }
    }
}
