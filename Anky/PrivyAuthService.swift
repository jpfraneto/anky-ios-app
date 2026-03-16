import Foundation
import PrivySDK

enum PrivyOAuthChoice: String, CaseIterable, Identifiable {
    case apple
    case google

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple:
            return "Apple"
        case .google:
            return "Google"
        }
    }

    fileprivate var provider: OAuthProvider {
        switch self {
        case .apple:
            return .apple
        case .google:
            return .google
        }
    }
}

@MainActor
final class PrivyAuthService {
    static let shared = PrivyAuthService()

    private let privy: any Privy
    private let appURLScheme: String

    private init() {
        appURLScheme = Bundle.main.bundleIdentifier ?? "com.jpfraneto.Anky"
        privy = PrivySdk.initialize(
            config: PrivyConfig(
                appId: "cmivv85zt00ftla0cjpaw155h",
                appClientId: "client-WY6TQNMf79CLc1pwhjeRdVbEdsaP85e9Esk8RLHPY9ebF"
            )
        )
    }

    func currentAccessToken() async throws -> String? {
        guard let user = await privy.getUser() else { return nil }
        return try await user.getAccessToken()
    }

    func sendEmailCode(to email: String) async throws {
        try await privy.email.sendCode(to: email)
    }

    func loginWithEmail(code: String, email: String) async throws -> String {
        let user = try await privy.email.loginWithCode(code, sentTo: email)
        return try await user.getAccessToken()
    }

    func loginWithOAuth(_ choice: PrivyOAuthChoice) async throws -> String {
        let user = try await privy.oAuth.login(with: choice.provider, appUrlScheme: appURLScheme)
        return try await user.getAccessToken()
    }

    func logout() async {
        guard let user = await privy.getUser() else { return }
        await user.logout()
    }
}
