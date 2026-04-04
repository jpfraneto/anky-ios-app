import Foundation
import Combine

class SharedSessionStore: ObservableObject {
    static let shared = SharedSessionStore()
    private let defaults = UserDefaults(suiteName: AppGroup.suiteName)

    @Published var state: AnkySessionState = AnkySessionState()

    func save(_ state: AnkySessionState) {
        if let data = try? JSONEncoder().encode(state) {
            defaults?.set(data, forKey: AppGroup.sessionStateKey)
        }
        DispatchQueue.main.async { self.state = state }
        postDarwinNotification()
    }

    func load() -> AnkySessionState {
        guard
            let data = defaults?.data(forKey: AppGroup.sessionStateKey),
            let decoded = try? JSONDecoder().decode(AnkySessionState.self, from: data)
        else { return AnkySessionState() }
        return decoded
    }

    func observeChanges(_ handler: @escaping () -> Void) {
        let name = "com.anky.sessionStateChanged" as CFString
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in },
            name, nil,
            .deliverImmediately
        )
    }

    private func postDarwinNotification() {
        let name = "com.anky.sessionStateChanged" as CFString
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name),
            nil, nil, true
        )
    }
}
