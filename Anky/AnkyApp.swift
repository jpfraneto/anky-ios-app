import SwiftUI
import UIKit

// MARK: - AppDelegate for Push Notifications

class AnkyAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            DeviceTokenManager.shared.sendTokenToServer(token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Push registration failed: \(error.localizedDescription)")
    }

    // Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Handle notification tap — open into writing with prompt
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let prompt = userInfo["prompt"] as? String, !prompt.isEmpty {
            Task { @MainActor in
                AnkyAppDelegate.pendingDeepLinkPrompt = prompt
            }
        }
        completionHandler()
    }

    /// Shared state for passing deep link prompt to AppState once it's ready.
    @MainActor static var pendingDeepLinkPrompt: String?
}

// MARK: - Device Token Manager

@MainActor
final class DeviceTokenManager {
    static let shared = DeviceTokenManager()

    private static let tokenKey = "anky.device.apnsToken"
    private var isSending = false

    var storedToken: String? {
        UserDefaults.standard.string(forKey: Self.tokenKey)
    }

    func registerForPushIfNeeded() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()

            if settings.authorizationStatus == .notDetermined {
                let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
                guard granted == true else { return }
            }

            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }

            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func sendTokenToServer(_ token: String) {
        // Save locally
        UserDefaults.standard.set(token, forKey: Self.tokenKey)

        guard !isSending else { return }
        isSending = true

        Task {
            defer { isSending = false }
            do {
                try await AnkyAPI.shared.registerDevice(token: token, platform: "ios")
            } catch {
                // Will retry on next app launch
            }
        }
    }

    func unregister() {
        guard let token = storedToken else { return }
        UserDefaults.standard.removeObject(forKey: Self.tokenKey)
        UIApplication.shared.unregisterForRemoteNotifications()

        Task {
            try? await AnkyAPI.shared.unregisterDevice(platform: "ios")
        }
    }
}

// MARK: - App

@main
struct AnkyApp: App {
    @UIApplicationDelegateAdaptor(AnkyAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState = AppState()
    @StateObject private var biometricLock = BiometricLockManager.shared

    init() {
        AnkyAudioSession.configureIfNeeded()
        FontRegistrar.registerBundledFonts()
        // Haptics are created on-demand via AnkyHaptics
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
            .environmentObject(appState)
            .environmentObject(biometricLock)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL {
                        handleIncomingURL(url)
                    }
                }
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .active:
                        Task {
                            await DailyPromptNotificationManager.rescheduleIfAuthorized()
                            guard appState.hasCompletedWelcome else { return }
                            _ = await biometricLock.unlockIfNeeded()

                            // Register for push after auth is ready
                            if appState.isAuthenticated {
                                DeviceTokenManager.shared.registerForPushIfNeeded()
                            }

                            // Deep link from notification tap
                            if let prompt = AnkyAppDelegate.pendingDeepLinkPrompt {
                                AnkyAppDelegate.pendingDeepLinkPrompt = nil
                                appState.deepLinkPrompt = prompt
                            }
                        }
                    case .background:
                        biometricLock.lock()
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        if url.scheme?.lowercased() == "anky" {
            handleCustomSchemeURL(url)
            return
        }

        handleUniversalLink(url)
    }

    private func handleCustomSchemeURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              components.host?.lowercased() == "seal",
              let token = components.queryItems?.first(where: { $0.name == "challenge" })?.value,
              !token.isEmpty else {
            return
        }

        appState.presentQRSealChallenge(token: token)
    }

    private func handleUniversalLink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return }

        // Seal challenge: https://anky.app/seal?challenge=<token>
        if components.path.hasPrefix("/seal") {
            if let token = components.queryItems?.first(where: { $0.name == "challenge" })?.value,
               !token.isEmpty {
                appState.presentQRSealChallenge(token: token)
            }
            return
        }

        // Now session: https://anky.app/n/{slug}
        if components.path.hasPrefix("/n/") {
            let slug = String(components.path.dropFirst(3))
            guard !slug.isEmpty else { return }
            appState.pendingNowSlug = slug
            return
        }

        // Shared anky: https://anky.app/anky/{id}
        if components.path.hasPrefix("/anky/") {
            let ankyId = String(components.path.dropFirst("/anky/".count))
            guard !ankyId.isEmpty else { return }
            appState.presentSharedAnky(id: ankyId)
            return
        }

        // Write deep link: https://anky.app/write?p=<UUID>
        guard components.path.hasPrefix("/write") else { return }

        guard let promptId = components.queryItems?.first(where: { $0.name == "p" })?.value,
              !promptId.isEmpty else { return }

        Task {
            do {
                let prompt = try await AnkyAPI.shared.getPrompt(id: promptId)
                appState.deepLinkPrompt = prompt.text
            } catch {
                appState.deepLinkPrompt = "write."
            }
        }
    }
}
