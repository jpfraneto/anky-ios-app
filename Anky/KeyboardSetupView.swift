import SwiftUI
import UIKit

struct KeyboardSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isKeyboardEnabled = false
    @State private var checkTimer: Timer?

    private let keyboardBundleID = "com.jpfraneto.Anky.AnkyKeyboard"

    var body: some View {
        ZStack {
            LinearGradient.ankyBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Close button
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.ankyMuted)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(Color.ankyPanel.opacity(0.8))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 20)
                    .padding(.top, 16)
                }

                Spacer(minLength: 20)

                if isKeyboardEnabled {
                    enabledState
                } else {
                    setupSteps
                }

                Spacer(minLength: 40)
            }
        }
        .onAppear {
            checkKeyboardStatus()
            // Poll every 2s so when user comes back from Settings it updates live
            checkTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                checkKeyboardStatus()
            }
        }
        .onDisappear {
            checkTimer?.invalidate()
        }
    }

    // MARK: - Setup steps

    private var setupSteps: some View {
        VStack(spacing: 32) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.ankyGold.opacity(0.5), .ankyAmber.opacity(0.2), .clear],
                            center: .center,
                            startRadius: 8,
                            endRadius: 80
                        )
                    )
                    .frame(width: 130, height: 130)

                Image(systemName: "keyboard")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(Color.ankyGold)
            }

            VStack(spacing: 12) {
                Text("Install Anky Keyboard")
                    .font(.anky(28))
                    .foregroundStyle(Color.ankyInk)

                Text("Write anywhere. Every app becomes a portal.")
                    .font(.anky(17))
                    .foregroundStyle(Color.ankyMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 32)
            }

            // Steps
            VStack(alignment: .leading, spacing: 20) {
                stepRow(number: 1, text: "Open Settings below")
                stepRow(number: 2, text: "Tap Keyboards")
                stepRow(number: 3, text: "Tap Add New Keyboard...")
                stepRow(number: 4, text: "Select Anky")
            }
            .padding(.horizontal, 40)

            // Open Settings button
            Button {
                openKeyboardSettings()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "gear")
                        .font(.system(size: 18, weight: .medium))
                    Text("Open Keyboard Settings")
                        .font(.anky(18))
                }
                .foregroundStyle(Color.ankyBlack)
                .frame(height: 56)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.ankyGold)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 28)

            Text("Come back here after — this screen updates automatically.")
                .font(.anky(13))
                .foregroundStyle(Color.ankyMuted.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Enabled state

    private var enabledState: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.ankyGold.opacity(0.6), .ankyAmber.opacity(0.2), .clear],
                            center: .center,
                            startRadius: 8,
                            endRadius: 80
                        )
                    )
                    .frame(width: 130, height: 130)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(Color.ankyGold)
            }

            VStack(spacing: 12) {
                Text("Anky Keyboard is active")
                    .font(.anky(28))
                    .foregroundStyle(Color.ankyInk)

                Text("Switch to Anky in any app by holding the globe key on your keyboard.")
                    .font(.anky(17))
                    .foregroundStyle(Color.ankyMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 32)
            }

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.anky(18))
                    .foregroundStyle(Color.ankyBlack)
                    .frame(height: 56)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.ankyGold)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Helpers

    private func stepRow(number: Int, text: String) -> some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(.anky(16))
                .foregroundStyle(Color.ankyBlack)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.ankyGold)
                )

            Text(text)
                .font(.anky(17))
                .foregroundStyle(Color.ankyInk)

            Spacer()
        }
    }

    private func openKeyboardSettings() {
        // Opens General > Keyboard settings — closest iOS allows
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func checkKeyboardStatus() {
        // Check if our keyboard extension is in the user's enabled keyboards
        let enabled = UITextInputMode.activeInputModes.contains { mode in
            mode.value(forKey: "identifier") as? String == keyboardBundleID
        }
        if enabled != isKeyboardEnabled {
            withAnimation(.easeInOut(duration: 0.4)) {
                isKeyboardEnabled = enabled
            }
        }
    }
}
