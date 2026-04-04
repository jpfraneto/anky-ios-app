import Combine
import Foundation
import LocalAuthentication

@MainActor
final class BiometricLockManager: ObservableObject {
    static let shared = BiometricLockManager()

    private static let enabledKey = "anky.biometric_lock_enabled"

    @Published var isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
    @Published var isUnlocked = !UserDefaults.standard.bool(forKey: enabledKey)
    @Published var lastError: String?
    private var isEvaluating = false

    private init() {}

    var biometryLabel: String {
        switch currentBiometryType() {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        default:
            return "device unlock"
        }
    }

    var isAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    var requiresUnlockOverlay: Bool {
        isEnabled && !isUnlocked
    }

    func enable() async -> Bool {
        guard isAvailable else {
            lastError = "\(biometryLabel) is not available on this device."
            isEnabled = false
            isUnlocked = true
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
            return false
        }

        let success = await evaluate(reason: "Unlock Anky.")
        if success {
            isEnabled = true
            isUnlocked = true
            lastError = nil
            UserDefaults.standard.set(true, forKey: Self.enabledKey)
        }
        return success
    }

    func disable() {
        isEnabled = false
        isUnlocked = true
        lastError = nil
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
    }

    func unlockIfNeeded() async -> Bool {
        guard isEnabled else {
            isUnlocked = true
            return true
        }
        guard !isUnlocked else { return true }
        guard !isEvaluating else { return false }

        let success = await evaluate(reason: "Unlock Anky.")
        if success {
            isUnlocked = true
            lastError = nil
        }
        return success
    }

    func reauthenticate(reason: String) async -> Bool {
        guard isAvailable else {
            return true
        }

        let success = await evaluate(reason: reason)
        if success {
            isUnlocked = true
            lastError = nil
        }
        return success
    }

    func lock() {
        guard isEnabled else { return }
        isUnlocked = false
    }

    private func evaluate(reason: String) async -> Bool {
        guard !isEvaluating else { return false }
        isEvaluating = true
        defer { isEvaluating = false }

        let context = LAContext()
        context.localizedCancelTitle = "Later"

        do {
            let success = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    continuation.resume(returning: success)
                }
            }

            return success
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func currentBiometryType() -> LABiometryType {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return context.biometryType
    }
}
