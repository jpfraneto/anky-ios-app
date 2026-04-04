//
//  UserSettings.swift
//  Anky
//

import Combine
import Foundation

@MainActor
final class UserSettings: ObservableObject {
    static let shared = UserSettings()

    private enum Keys {
        static let preferredLanguage = "anky.settings.preferredLanguage"
        static let fontSize = "anky.settings.fontSize"
        static let lastPlayedStoryId = "anky.playback.lastStoryId"
        static let lastPlayedPosition = "anky.playback.lastPosition"
        static let completedStoryIds = "anky.playback.completedStoryIds"
        static let didSyncFromServer = "anky.settings.didSyncFromServer"
        static let remindersEnabled = "anky.settings.remindersEnabled"
        static let reminderHour = "anky.settings.reminderHour"
        static let reminderMinute = "anky.settings.reminderMinute"
    }

    @Published var preferredLanguageId: String {
        didSet {
            UserDefaults.standard.set(preferredLanguageId, forKey: Keys.preferredLanguage)
            syncToServer()
        }
    }

    @Published var fontSize: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(fontSize), forKey: Keys.fontSize)
            syncToServer()
        }
    }

    @Published var lastPlayedStoryId: String? {
        didSet { UserDefaults.standard.set(lastPlayedStoryId, forKey: Keys.lastPlayedStoryId) }
    }

    @Published var lastPlayedPosition: Double {
        didSet { UserDefaults.standard.set(lastPlayedPosition, forKey: Keys.lastPlayedPosition) }
    }

    @Published var completedStoryIds: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(completedStoryIds), forKey: Keys.completedStoryIds)
        }
    }

    @Published var remindersEnabled: Bool {
        didSet {
            UserDefaults.standard.set(remindersEnabled, forKey: Keys.remindersEnabled)
            if remindersEnabled {
                Task { await DailyPromptNotificationManager.rescheduleIfAuthorized() }
            } else {
                DailyPromptNotificationManager.cancel()
            }
        }
    }

    @Published var reminderHour: Int {
        didSet {
            UserDefaults.standard.set(reminderHour, forKey: Keys.reminderHour)
            if remindersEnabled {
                Task { await DailyPromptNotificationManager.rescheduleIfAuthorized() }
            }
        }
    }

    @Published var reminderMinute: Int {
        didSet {
            UserDefaults.standard.set(reminderMinute, forKey: Keys.reminderMinute)
            if remindersEnabled {
                Task { await DailyPromptNotificationManager.rescheduleIfAuthorized() }
            }
        }
    }

    private var syncTask: Task<Void, Never>?

    init() {
        let deviceLang = String(Locale.current.language.languageCode?.identifier.prefix(2) ?? "en")
        let storedLang = UserDefaults.standard.string(forKey: Keys.preferredLanguage)
        self.preferredLanguageId = storedLang ?? deviceLang

        let storedSize = UserDefaults.standard.double(forKey: Keys.fontSize)
        self.fontSize = storedSize > 0 ? CGFloat(storedSize) : 20

        self.lastPlayedStoryId = UserDefaults.standard.string(forKey: Keys.lastPlayedStoryId)
        self.lastPlayedPosition = UserDefaults.standard.double(forKey: Keys.lastPlayedPosition)

        let stored = UserDefaults.standard.stringArray(forKey: Keys.completedStoryIds) ?? []
        self.completedStoryIds = Set(stored)

        self.remindersEnabled = UserDefaults.standard.bool(forKey: Keys.remindersEnabled)
        let storedHour = UserDefaults.standard.object(forKey: Keys.reminderHour) as? Int
        self.reminderHour = storedHour ?? 8
        let storedMinute = UserDefaults.standard.object(forKey: Keys.reminderMinute) as? Int
        self.reminderMinute = storedMinute ?? 0
    }

    // MARK: - Server Sync

    /// Pull settings from server (call after auth). Server wins on first sync,
    /// local wins after that (user's most recent change takes priority).
    func syncFromServer() async {
        do {
            let remote = try await AnkyAPI.shared.getSettings()
            let didSyncBefore = UserDefaults.standard.bool(forKey: Keys.didSyncFromServer)

            if !didSyncBefore {
                // First sync — server values override local
                if let lang = remote.preferredLanguage, !lang.isEmpty {
                    preferredLanguageId = lang
                }
                if let size = remote.fontSize, size > 0 {
                    fontSize = CGFloat(size)
                }
                UserDefaults.standard.set(true, forKey: Keys.didSyncFromServer)
            }
            // After first sync, local changes push to server via syncToServer()
        } catch {
            // Offline or unauthenticated — use local settings
        }
    }

    private func syncToServer() {
        syncTask?.cancel()
        syncTask = Task {
            // Debounce — wait a moment for rapid changes (e.g. slider)
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }

            let update = UserSettingsUpdate(
                preferredLanguage: preferredLanguageId,
                fontSize: Int(fontSize)
            )
            _ = try? await AnkyAPI.shared.patchSettings(update)
        }
    }

    // MARK: - Story Tracking

    func markStoryCompleted(_ storyId: String) {
        completedStoryIds.insert(storyId)
    }

    func isStoryCompleted(_ storyId: String) -> Bool {
        completedStoryIds.contains(storyId)
    }

    func savePlaybackPosition(storyId: String, position: Double) {
        lastPlayedStoryId = storyId
        lastPlayedPosition = position
    }

    func resumePosition(for storyId: String) -> Double? {
        guard lastPlayedStoryId == storyId, lastPlayedPosition > 0 else { return nil }
        return lastPlayedPosition
    }

    func clearPlaybackPosition() {
        lastPlayedStoryId = nil
        lastPlayedPosition = 0
    }

    var preferredStoryLanguage: StoryLanguage {
        StoryLanguage.available.first { $0.id == preferredLanguageId }
            ?? StoryLanguage.available[0]
    }
}
