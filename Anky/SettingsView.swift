//
//  SettingsView.swift
//  Anky
//

import SafariServices
import SwiftUI
import UIKit

private struct SettingsDocument: Identifiable, Hashable {
    let title: String
    let url: URL

    var id: String { title }
}

private struct SettingsNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum PremiumPlan: String, CaseIterable, Identifiable {
    case yearly
    case monthly
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yearly: return "Yearly"
        case .monthly: return "Monthly"
        case .weekly: return "Weekly"
        }
    }

    var subtitle: String {
        switch self {
        case .yearly: return "Best pace for a full season of practice"
        case .monthly: return "A lighter commitment with room to settle in"
        case .weekly: return "A short preview once billing is live"
        }
    }

    var previewLabel: String {
        switch self {
        case .yearly: return "MOST GROUNDED"
        case .monthly: return "FLEXIBLE"
        case .weekly: return "LIGHT ENTRY"
        }
    }

    var badge: String? {
        switch self {
        case .yearly: return "Recommended"
        case .monthly: return nil
        case .weekly: return nil
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = UserSettings.shared

    @State private var walletAddress = ""
    @State private var copiedWallet = false
    @State private var showSeedBackup = false
    @State private var selectedDocument: SettingsDocument?
    @State private var connectedDevices: [ConnectedDevice] = []
    @State private var isLoadingConnectedDevices = false
    @State private var connectedDevicesError: String?
    @State private var revokingDeviceIDs: Set<String> = []
    @State private var devicePendingRevocation: ConnectedDevice?
    @State private var showPremiumSheet = false
    @State private var selectedPremiumPlan: PremiumPlan = .yearly
    @State private var notice: SettingsNotice?
    @State private var isConfirmingReboot = false

    private let legalDocuments: [SettingsDocument] = [
        SettingsDocument(
            title: "Terms of Service",
            url: URL(string: "https://anky.app/terms-of-service.md")!
        ),
        SettingsDocument(
            title: "Privacy Policy",
            url: URL(string: "https://anky.app/privacy-policy.md")!
        ),
        SettingsDocument(
            title: "Frequently Asked Questions",
            url: URL(string: "https://anky.app/faq.md")!
        )
    ]

    private var appVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "v\(shortVersion) (\(buildNumber))"
    }

    private var displayedConnectedDevices: [ConnectedDevice] {
        connectedDevices.sorted { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent {
                return lhs.isCurrent && !rhs.isCurrent
            }
            if lhs.isRevoked != rhs.isRevoked {
                return !lhs.isRevoked && rhs.isRevoked
            }
            return deviceSortDate(for: lhs) > deviceSortDate(for: rhs)
        }
    }

    private var isPremiumUser: Bool {
        appState.user?.isPremium == true
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header
                writingSection
                identitySection
                connectedDevicesSection
                premiumSection
                formalitiesSection
                dangerSection
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(settingsBackground.ignoresSafeArea())
        .refreshable {
            await loadConnectedDevices(showUnsupportedMessage: connectedDevicesError != nil)
        }
        .task {
            loadWalletAddress()
            await loadConnectedDevices(showUnsupportedMessage: appState.isAuthenticated)
        }
        .fullScreenCover(isPresented: $showSeedBackup) {
            SeedPhraseBackupView()
                .environmentObject(appState)
        }
        .sheet(item: $selectedDocument) { document in
            SettingsSafariView(document: document)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showPremiumSheet) {
            PremiumSubscriptionSheet(
                selectedPlan: $selectedPremiumPlan,
                isPremium: isPremiumUser
            )
            .presentationDetents([.fraction(0.92), .large])
            .presentationDragIndicator(.hidden)
            .sheetStyleBackground(Color.ankyBg)
        }
        .confirmationDialog(
            "Revoke this device?",
            isPresented: Binding(
                get: { devicePendingRevocation != nil },
                set: { isPresented in
                    if !isPresented {
                        devicePendingRevocation = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let devicePendingRevocation {
                Button("Revoke", role: .destructive) {
                    Task { await revokeDevice(devicePendingRevocation) }
                }
            }
            Button("Cancel", role: .cancel) {
                devicePendingRevocation = nil
            }
        } message: {
            if let devicePendingRevocation {
                Text("\(deviceTitle(for: devicePendingRevocation)) will need to sign in again to reconnect.")
            }
        }
        .confirmationDialog("Reboot identity?", isPresented: $isConfirmingReboot, titleVisibility: .visible) {
            Button("Reboot identity", role: .destructive) {
                Task {
                    await appState.rebootIdentity()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the local key, drafts, and cached history on this iPhone. It cannot be undone.")
        }
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Settings")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.ankyTextPrimary)

                Text("Quiet control over writing, identity, connected devices, and the shape of your account.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.ankyTextSecondary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ankyTextPrimary.opacity(0.88))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var writingSection: some View {
        settingsSection(
            title: "Writing",
            caption: "Keep the writing surface readable without adding chrome."
        ) {
            settingsCard {
                HStack(spacing: 14) {
                    sizeButton(systemName: "minus") {
                        adjustFontSize(by: -1)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Text size")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.ankyTextPrimary)

                        Text("\(Int(settings.fontSize)) pt in the active writing view")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color.ankyTextSecondary)
                    }

                    Spacer(minLength: 0)

                    sizeButton(systemName: "plus") {
                        adjustFontSize(by: 1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)

                settingsDivider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Preview")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ankyTextMuted.opacity(0.95))
                        .textCase(.uppercase)

                    Text("When the page gets quiet, the next honest word matters.")
                        .font(.custom("Georgia", size: settings.fontSize))
                        .lineSpacing(max(6, settings.fontSize * 0.28))
                        .foregroundStyle(Color.ankyTextPrimary.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
    }

    private var identitySection: some View {
        settingsSection(
            title: "Identity",
            caption: "Your seed stays local. These controls only help you inspect and protect it."
        ) {
            settingsCard {
                Button {
                    copyWalletAddress()
                } label: {
                    settingsRow(
                        icon: "wallet.pass.fill",
                        title: "Wallet address",
                        subtitle: walletAddress.isEmpty ? "Not available on this device yet" : truncatedWalletAddress(walletAddress),
                        trailingLabel: copiedWallet ? "Copied" : "Copy",
                        trailingAccent: copiedWallet ? Color(hex: "4a8a4a") : Color.ankyTextPrimary.opacity(0.88)
                    )
                }
                .buttonStyle(.plain)

                settingsDivider()

                Button {
                    showSeedBackup = true
                } label: {
                    settingsRow(
                        icon: "key.fill",
                        title: "Recovery phrase",
                        subtitle: appState.hasBackedUpPhrase ? "Already secured on paper" : "Reveal and secure the phrase",
                        trailingLabel: appState.hasBackedUpPhrase ? "Backed up" : "Open",
                        trailingAccent: appState.hasBackedUpPhrase ? Color(hex: "c4845a") : Color.ankyTextPrimary.opacity(0.88),
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var connectedDevicesSection: some View {
        settingsSection(
            title: "Connected Devices",
            caption: "Telegram-style account sessions. Current device stays pinned to the top and other sessions can be revoked."
        ) {
            settingsCard {
                if isLoadingConnectedDevices && displayedConnectedDevices.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(Color(hex: "c4845a"))
                        Text("Loading connected devices...")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Color.ankyTextSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                } else {
                    ForEach(Array(displayedConnectedDevices.enumerated()), id: \.element.id) { index, device in
                        connectedDeviceRow(device)
                        if index < displayedConnectedDevices.count - 1 {
                            settingsDivider()
                        }
                    }

                    if !displayedConnectedDevices.isEmpty {
                        settingsDivider()
                    }

                    Button {
                        Task { await loadConnectedDevices(showUnsupportedMessage: true) }
                    } label: {
                        HStack(spacing: 10) {
                            if isLoadingConnectedDevices {
                                ProgressView()
                                    .tint(Color(hex: "c4845a"))
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .semibold))
                            }

                            Text(isLoadingConnectedDevices ? "Refreshing sessions..." : "Refresh device list")
                                .font(.system(size: 14, weight: .medium))

                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Color.ankyTextPrimary.opacity(0.86))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingConnectedDevices)
                }
            }

            if let connectedDevicesError {
                Text(connectedDevicesError)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.ankyTextSecondary.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var premiumSection: some View {
        settingsSection(
            title: "Premium",
            caption: "Preview the premium membership sheet from settings. Checkout still stays in preview until billing is fully wired."
        ) {
            settingsCard {
                Button {
                    showPremiumSheet = true
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "f8da59"), Color(hex: "d5a62b")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 42, height: 42)

                            Image(systemName: isPremiumUser ? "checkmark.seal.fill" : "sparkles")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.82))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(isPremiumUser ? "Premium active" : "Subscribe to Premium")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.ankyTextPrimary)

                            Text(isPremiumUser ? "Your account already carries premium access." : "Open the new bottom sheet and preview the premium plans.")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(Color.ankyTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)

                        HStack(spacing: 8) {
                            Text(isPremiumUser ? "Active" : "Preview")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isPremiumUser ? Color(hex: "4a8a4a") : Color(hex: "c4845a"))

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.ankyTextMuted.opacity(0.9))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var formalitiesSection: some View {
        settingsSection(
            title: "Formalities",
            caption: "Legal and help pages stay inside the app in native Safari."
        ) {
            settingsCard {
                ForEach(Array(legalDocuments.enumerated()), id: \.element.id) { index, document in
                    Button {
                        selectedDocument = document
                    } label: {
                        settingsRow(
                            icon: formalitiesIcon(for: document.title),
                            title: document.title,
                            subtitle: document.url.host ?? "anky.app",
                            trailingLabel: nil,
                            trailingAccent: Color.ankyTextPrimary,
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.plain)

                    if index < legalDocuments.count - 1 {
                        settingsDivider()
                    }
                }
            }
        }
    }

    private var dangerSection: some View {
        settingsSection(
            title: "Danger",
            caption: "This is the irreversible one."
        ) {
            settingsCard {
                Button(role: .destructive) {
                    isConfirmingReboot = true
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.red.opacity(0.14))
                                .frame(width: 42, height: 42)

                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.red.opacity(0.82))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reboot identity")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.red.opacity(0.88))

                            Text("Delete the local key, drafts, and cached archive on this iPhone.")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(Color.ankyTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.ankyTextMuted.opacity(0.9))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Text("Created with 💚 by Anky, Inc.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.ankyTextSecondary.opacity(0.92))

            Text(appVersion)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.ankyTextMuted.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private var settingsBackground: some View {
        ZStack {
            Color.ankyBg

            LinearGradient(
                colors: [
                    Color(hex: "1e1708").opacity(0.55),
                    Color.clear,
                    Color(hex: "0f1a10").opacity(0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(hex: "c4845a").opacity(0.08))
                .blur(radius: 80)
                .frame(width: 240, height: 240)
                .offset(x: -120, y: -220)
        }
    }

    private func adjustFontSize(by delta: CGFloat) {
        let proposed = settings.fontSize + delta
        settings.fontSize = min(max(proposed, 14), 30)
    }

    private func loadWalletAddress() {
        walletAddress = (try? SeedIdentityManager.shared.walletAddress()) ?? ""
    }

    @MainActor
    private func loadConnectedDevices(showUnsupportedMessage: Bool) async {
        isLoadingConnectedDevices = true
        defer { isLoadingConnectedDevices = false }

        do {
            let remoteDevices = try await AnkyAPI.shared.connectedDevices()
            connectedDevices = mergedConnectedDevices(from: remoteDevices)
            connectedDevicesError = nil
        } catch {
            connectedDevices = mergedConnectedDevices(from: [])
            if showUnsupportedMessage {
                connectedDevicesError = connectedDevicesFallbackMessage(for: error)
            } else {
                connectedDevicesError = nil
            }
        }
    }

    @MainActor
    private func revokeDevice(_ device: ConnectedDevice) async {
        guard device.canRevoke else { return }

        revokingDeviceIDs.insert(device.id)
        defer {
            revokingDeviceIDs.remove(device.id)
            devicePendingRevocation = nil
        }

        do {
            try await AnkyAPI.shared.revokeConnectedDevice(id: device.id)
            connectedDevices.removeAll { $0.id == device.id }
            connectedDevices = mergedConnectedDevices(from: connectedDevices)
            notice = SettingsNotice(
                title: "Device revoked",
                message: "\(deviceTitle(for: device)) will need to sign in again before it can reconnect."
            )
        } catch {
            notice = SettingsNotice(
                title: "Couldn't revoke device",
                message: revokeErrorMessage(for: error)
            )
        }
    }

    private func mergedConnectedDevices(from devices: [ConnectedDevice]) -> [ConnectedDevice] {
        var merged = devices
        if !merged.contains(where: \.isCurrent) {
            merged.insert(.currentFallback(appVersion: appVersion), at: 0)
        }

        var deduped: [ConnectedDevice] = []
        var seen = Set<String>()

        for device in merged where seen.insert(device.id).inserted {
            deduped.append(device)
        }

        return deduped
    }

    private func copyWalletAddress() {
        guard !walletAddress.isEmpty else { return }

        UIPasteboard.general.string = walletAddress
        copiedWallet = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            copiedWallet = false
        }
    }

    private func connectedDevicesFallbackMessage(for error: Error) -> String {
        if let ankyError = error as? AnkyError {
            switch ankyError {
            case .unauthorized:
                return "Anky needs to quietly restore the session before it can list every connected device. This iPhone is still shown locally."
            case .transport:
                return "The full device list could not load right now. Showing this iPhone from local context until the network settles."
            case .api(let message):
                let lowered = message.lowercased()
                if lowered.contains("not found")
                    || lowered.contains("cannot get")
                    || lowered.contains("not implemented")
                    || lowered.contains("unknown route") {
                    return "This settings screen is ready for the backend device-session endpoint. Until `/auth/sessions` is live, the current iPhone is shown locally."
                }
                return "The device list did not load cleanly. Showing the current iPhone while the server response is sorted out."
            default:
                break
            }
        }

        return "The full device list is unavailable right now. Showing the current iPhone from local context."
    }

    private func revokeErrorMessage(for error: Error) -> String {
        if let ankyError = error as? AnkyError {
            switch ankyError {
            case .transport:
                return "The revoke request did not reach Anky. Please try again when the connection is stable."
            case .api(let message):
                return message
            case .unauthorized:
                return "Your session needs to be refreshed before this device can be revoked."
            default:
                break
            }
        }

        return error.localizedDescription
    }

    private func truncatedWalletAddress(_ value: String) -> String {
        guard value.count > 12 else { return value }
        return "\(value.prefix(6))...\(value.suffix(6))"
    }

    private func settingsSection<Content: View>(
        title: String,
        caption: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Color.ankyTextMuted.opacity(0.95))

                if let caption {
                    Text(caption)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.ankyTextSecondary.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content()
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.ankyCardBg.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }

    private func settingsDivider() -> some View {
        Rectangle()
            .fill(Color.ankyDivider.opacity(1.8))
            .frame(height: 1)
            .padding(.leading, 58)
    }

    private func sizeButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.ankyTextPrimary.opacity(0.92))
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }

    private func settingsRow(
        icon: String,
        title: String,
        subtitle: String,
        trailingLabel: String?,
        trailingAccent: Color,
        showsChevron: Bool = false
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 42, height: 42)

                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.ankyTextPrimary.opacity(0.88))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.ankyTextPrimary)

                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.ankyTextSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            if let trailingLabel {
                Text(trailingLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(trailingAccent)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ankyTextMuted.opacity(0.9))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private func connectedDeviceRow(_ device: ConnectedDevice) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 42, height: 42)

                Image(systemName: deviceIconName(for: device))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.ankyTextPrimary.opacity(0.88))
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(deviceTitle(for: device))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.ankyTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if device.isCurrent {
                        statusPill(label: "Current", color: Color(hex: "c4845a"))
                    } else if device.isRevoked {
                        statusPill(label: "Revoked", color: Color.red.opacity(0.75))
                    }
                }

                Text(deviceDetailLine(for: device))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.ankyTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(deviceActivityLine(for: device))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.ankyTextMuted.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if revokingDeviceIDs.contains(device.id) {
                ProgressView()
                    .tint(Color(hex: "c4845a"))
                    .padding(.top, 10)
            } else if device.canRevoke {
                Button(role: .destructive) {
                    devicePendingRevocation = device
                } label: {
                    Text("Revoke")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.86))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color.red.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private func statusPill(label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }

    private func deviceIconName(for device: ConnectedDevice) -> String {
        let source = [
            device.deviceName,
            device.model,
            device.platform
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        if source.contains("ipad") {
            return "ipad"
        }
        if source.contains("mac") || source.contains("desktop") {
            return "desktopcomputer"
        }
        if source.contains("laptop") {
            return "laptopcomputer"
        }
        if source.contains("android") {
            return "smartphone"
        }
        return "iphone"
    }

    private func deviceTitle(for device: ConnectedDevice) -> String {
        if device.isCurrent {
            return UIDevice.current.name
        }

        if let deviceName = trimmed(device.deviceName) {
            return deviceName
        }
        if let model = trimmed(device.model) {
            return model
        }
        if let platform = trimmed(device.platform) {
            return platform.capitalized
        }
        return "Connected device"
    }

    private func deviceDetailLine(for device: ConnectedDevice) -> String {
        var parts: [String] = []

        if let platform = trimmed(device.platform) {
            if let osVersion = trimmed(device.osVersion) {
                parts.append("\(platform.capitalized) \(osVersion)")
            } else {
                parts.append(platform.capitalized)
            }
        }

        if let appVersion = trimmed(device.appVersion) {
            parts.append("Anky \(appVersion)")
        }

        if let location = trimmed(device.location) {
            parts.append(location)
        } else if let ipAddress = trimmed(device.ipAddress) {
            parts.append(ipAddress)
        }

        if parts.isEmpty {
            return "No extra device details yet"
        }

        return parts.joined(separator: " · ")
    }

    private func deviceActivityLine(for device: ConnectedDevice) -> String {
        if device.isRevoked, let revokedAt = SettingsDateParser.parse(device.revokedAt) {
            return "Revoked \(SettingsDateParser.relativeString(for: revokedAt))"
        }

        if let lastSeen = SettingsDateParser.parse(device.lastSeenAt) {
            return device.isCurrent
                ? "Active on this iPhone · last seen \(SettingsDateParser.relativeString(for: lastSeen))"
                : "Last seen \(SettingsDateParser.relativeString(for: lastSeen))"
        }

        if let createdAt = SettingsDateParser.parse(device.createdAt) {
            return "Connected \(SettingsDateParser.relativeString(for: createdAt))"
        }

        return device.isCurrent ? "This device is holding the current session." : "Connected to this account."
    }

    private func deviceSortDate(for device: ConnectedDevice) -> Date {
        SettingsDateParser.parse(device.lastSeenAt)
            ?? SettingsDateParser.parse(device.createdAt)
            ?? .distantPast
    }

    private func formalitiesIcon(for title: String) -> String {
        switch title {
        case "Terms of Service":
            return "doc.text.fill"
        case "Privacy Policy":
            return "hand.raised.fill"
        default:
            return "questionmark.circle.fill"
        }
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct SettingsSafariView: UIViewControllerRepresentable {
    let document: SettingsDocument

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: document.url)
        controller.dismissButtonStyle = .close
        controller.preferredControlTintColor = UIColor(Color(hex: "c4845a"))
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private struct PremiumSubscriptionSheet: View {
    @Binding var selectedPlan: PremiumPlan

    let isPremium: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDocument: SettingsDocument?
    @State private var notice: SettingsNotice?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                HStack {
                    Capsule()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 56, height: 5)

                    Spacer(minLength: 0)

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.ankyTextPrimary.opacity(0.9))
                            .frame(width: 34, height: 34)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.07))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 10)

                PremiumHeroStrip()

                VStack(spacing: 8) {
                    Text("Subscribe to Premium")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)

                    Text(isPremium ? "This account already carries premium access." : "A calmer premium flow for people who want to support the work and go deeper with Anky.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.64))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 12) {
                    PremiumBenefitRow(
                        icon: "heart.fill",
                        title: "Support the quiet work behind Anky",
                        detail: "Premium gives the product a path that is calmer than ads, spam, or noisy growth tactics."
                    )
                    PremiumBenefitRow(
                        icon: "sparkles",
                        title: "One place for deeper membership rituals",
                        detail: "This sheet becomes the home for premium features as they land, without scattering them around the app."
                    )
                    PremiumBenefitRow(
                        icon: "lock.shield.fill",
                        title: "No fake checkout",
                        detail: "The design is ready now, but purchase and restore stay explicit previews until billing is real."
                    )
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                )

                VStack(spacing: 12) {
                    ForEach(PremiumPlan.allCases) { plan in
                        PremiumPlanCard(
                            plan: plan,
                            isSelected: selectedPlan == plan
                        ) {
                            selectedPlan = plan
                        }
                    }
                }

                Button {
                    if isPremium {
                        dismiss()
                    } else {
                        notice = SettingsNotice(
                            title: "Premium checkout preview",
                            message: "The paywall UI is in place, but StoreKit products and restore flow are not wired in this build yet."
                        )
                    }
                } label: {
                    Text(isPremium ? "Premium is already active" : "Continue with \(selectedPlan.title)")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.84))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "f8da59"), Color(hex: "e2b833")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(isPremium)
                .opacity(isPremium ? 0.65 : 1)

                VStack(spacing: 10) {
                    Text("Cancel anytime. App Store pricing and restore behavior will appear here once billing is configured.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.48))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 16) {
                        Button("Terms") {
                            selectedDocument = SettingsDocument(
                                title: "Terms of Service",
                                url: URL(string: "https://anky.app/terms-of-service.md")!
                            )
                        }
                        .buttonStyle(.plain)

                        Button("Privacy") {
                            selectedDocument = SettingsDocument(
                                title: "Privacy Policy",
                                url: URL(string: "https://anky.app/privacy-policy.md")!
                            )
                        }
                        .buttonStyle(.plain)

                        Button("Restore") {
                            notice = SettingsNotice(
                                title: "Restore not wired yet",
                                message: "Restore will work once StoreKit products and purchase state are connected."
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(sheetBackground.ignoresSafeArea())
        .sheet(item: $selectedDocument) { document in
            SettingsSafariView(document: document)
                .ignoresSafeArea()
        }
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var sheetBackground: some View {
        ZStack {
            Color.ankyBg

            LinearGradient(
                colors: [
                    Color(hex: "362707").opacity(0.8),
                    Color(hex: "121016").opacity(0.98),
                    Color(hex: "0b120d").opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(Color(hex: "f6cd48").opacity(0.16))
                .blur(radius: 90)
                .frame(width: 280, height: 280)
                .offset(x: 120, y: -220)

            Circle()
                .fill(Color(hex: "4a8a4a").opacity(0.08))
                .blur(radius: 100)
                .frame(width: 260, height: 260)
                .offset(x: -120, y: -120)
        }
    }
}

private struct PremiumHeroStrip: View {
    private let cards: [(Color, Color, String)] = [
        (Color(hex: "6e4f1e"), Color(hex: "f0d06f"), "moon.stars.fill"),
        (Color(hex: "3e2c13"), Color(hex: "ffd966"), "book.closed.fill"),
        (Color(hex: "24412a"), Color(hex: "d4ef8e"), "leaf.fill"),
        (Color(hex: "3b2714"), Color(hex: "ffd15c"), "sparkles"),
        (Color(hex: "16242d"), Color(hex: "a9d8ff"), "circle.hexagongrid.fill")
    ]

    var body: some View {
        ZStack {
            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [card.0, card.1.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: card.2)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.88))
                    )
                    .frame(width: 84, height: 112)
                    .rotationEffect(.degrees(heroRotation(for: index)))
                    .offset(x: heroOffsetX(for: index), y: heroOffsetY(for: index))
                    .shadow(color: Color.black.opacity(0.22), radius: 14, y: 8)
            }
        }
        .frame(height: 150)
    }

    private func heroRotation(for index: Int) -> Double {
        [-12, -5, 0, 7, 13][index]
    }

    private func heroOffsetX(for index: Int) -> CGFloat {
        [-122, -58, 0, 58, 122][index]
    }

    private func heroOffsetY(for index: Int) -> CGFloat {
        [6, -4, 10, -2, 8][index]
    }
}

private struct PremiumBenefitRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "f6cd48"))
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.94))

                Text(detail)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PremiumPlanCard: View {
    let plan: PremiumPlan
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.96))

                        if let badge = plan.badge {
                            Text(badge.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.9)
                                .foregroundStyle(Color.black.opacity(0.85))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(Color(hex: "f6cd48"))
                                )
                        }
                    }

                    Text(plan.subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(plan.previewLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(isSelected ? Color(hex: "f6cd48") : Color.white.opacity(0.44))
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .stroke(isSelected ? Color(hex: "f6cd48") : Color.white.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 28, height: 28)

                    if isSelected {
                        Circle()
                            .fill(Color(hex: "f6cd48"))
                            .frame(width: 18, height: 18)

                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.84))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.085 : 0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(isSelected ? Color(hex: "f6cd48") : Color.white.opacity(0.08), lineWidth: 1.2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private enum SettingsDateParser {
    static let isoWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return isoWithFractional.date(from: value) ?? iso.date(from: value)
    }

    static func relativeString(for date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: .now)
    }
}
