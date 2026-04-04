//
//  AltarView.swift
//  Anky
//

import Combine
import SwiftUI
#if canImport(PassKit)
import PassKit
#endif
#if canImport(StripeApplePay)
import StripeApplePay
#endif

@MainActor
final class AltarViewModel: NSObject, ObservableObject {
    @Published var altar: AltarState?
    @Published var burnAmountText = ""
    @Published var isLoading = false
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    @Published var imageGlowBoost = false
    @Published var hasPendingBurnSync = false

    private let merchantIdentifier = "merchant.com.jpfraneto.anky"
    private var currentBurnRequest: RecordApplePayBurnRequest?

    #if canImport(StripeApplePay) && canImport(PassKit)
    private var applePayContext: STPApplePayContext?
    private var currentClientSecret: String?
    #endif

    func loadIfNeeded() async {
        if altar == nil {
            await refresh()
        }
        await syncPendingBurn(showErrors: false)
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            altar = try await AnkyAPI.shared.altar()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        hasPendingBurnSync = PendingBurnSyncStore.load() != nil
    }

    func sanitizeAmountInput() {
        let filtered = burnAmountText.filter { $0.isNumber || $0 == "." }
        let parts = filtered.split(separator: ".", omittingEmptySubsequences: false)

        let normalized: String
        if parts.count <= 1 {
            normalized = String(filtered.prefix(7))
        } else {
            let whole = String(parts[0].prefix(7))
            let decimals = String(parts[1].prefix(2))
            normalized = whole + "." + decimals
        }

        if normalized != burnAmountText {
            burnAmountText = normalized
        }
    }

    var canBeginBurn: Bool {
        burnAmountCents != nil && !isSubmitting
    }

    func beginBurn(using appState: AppState) {
        Task {
            await startBurn(using: appState)
        }
    }

    func retryPendingBurnSync() {
        Task {
            await syncPendingBurn(showErrors: true)
        }
    }

    private func startBurn(using appState: AppState) async {
        guard let amountCents = burnAmountCents else {
            errorMessage = "Enter an amount to burn."
            return
        }

        guard let publishableKey = altar?.stripePublishableKey, !publishableKey.isEmpty else {
            errorMessage = "The altar isn't ready for Apple Pay yet."
            return
        }

        let solanaAddress: String
        do {
            solanaAddress = try SeedIdentityManager.shared.solanaAddress()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let displayName = [appState.user?.displayName, appState.user?.username]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })

        #if canImport(StripeApplePay) && canImport(PassKit)
        guard StripeAPI.deviceSupportsApplePay() else {
            errorMessage = "Apple Pay isn't available on this device."
            return
        }

        isSubmitting = true
        errorMessage = nil

        do {
            let paymentIntent = try await AnkyAPI.shared.createAltarPaymentIntent(amountCents: amountCents)
            currentBurnRequest = RecordApplePayBurnRequest(
                paymentIntentId: paymentIntent.paymentIntentId,
                solanaAddress: solanaAddress,
                displayName: displayName
            )
            currentClientSecret = paymentIntent.clientSecret

            StripeAPI.defaultPublishableKey = publishableKey

            let dollars = Decimal(amountCents) / Decimal(100)
            let paymentRequest = StripeAPI.paymentRequest(
                withMerchantIdentifier: merchantIdentifier,
                country: "US",
                currency: "usd"
            )
            paymentRequest.paymentSummaryItems = [
                PKPaymentSummaryItem(
                    label: "Offering to the Altar",
                    amount: NSDecimalNumber(decimal: dollars)
                )
            ]

            guard let context = STPApplePayContext(paymentRequest: paymentRequest, delegate: self) else {
                resetPaymentState()
                errorMessage = "Apple Pay isn't configured correctly yet."
                return
            }

            guard let presenter = UIApplication.shared.topViewController() else {
                resetPaymentState()
                errorMessage = "Couldn't present Apple Pay right now."
                return
            }

            applePayContext = context
            context.presentApplePay(on: presenter)
        } catch {
            resetPaymentState()
            errorMessage = error.localizedDescription
        }
        #else
        errorMessage = "Stripe Apple Pay support isn't available in this build."
        #endif
    }

    private func finalizeBurn(afterSuccessfulApplePay request: RecordApplePayBurnRequest) async {
        do {
            let updatedState = try await AnkyAPI.shared.recordApplePayBurn(
                paymentIntentId: request.paymentIntentId,
                solanaAddress: request.solanaAddress,
                displayName: request.displayName
            )

            altar = updatedState
            burnAmountText = ""
            errorMessage = nil
            PendingBurnSyncStore.clear()
            hasPendingBurnSync = false
            triggerSuccessEffects()
        } catch {
            PendingBurnSyncStore.save(request)
            hasPendingBurnSync = true
            errorMessage = "Apple Pay succeeded, but syncing the burn failed. Retry sync below."
        }

        resetPaymentState()
    }

    private func syncPendingBurn(showErrors: Bool) async {
        guard let pending = PendingBurnSyncStore.load() else {
            hasPendingBurnSync = false
            return
        }

        do {
            let updatedState = try await AnkyAPI.shared.recordApplePayBurn(
                paymentIntentId: pending.paymentIntentId,
                solanaAddress: pending.solanaAddress,
                displayName: pending.displayName
            )
            altar = updatedState
            PendingBurnSyncStore.clear()
            hasPendingBurnSync = false
            if showErrors {
                errorMessage = nil
            }
        } catch {
            hasPendingBurnSync = true
            if showErrors {
                errorMessage = "The burn is still waiting to sync."
            }
        }
    }

    private func triggerSuccessEffects() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        withAnimation(.easeOut(duration: 0.18)) {
            imageGlowBoost = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.45)) {
                self.imageGlowBoost = false
            }
        }
    }

    private func resetPaymentState() {
        isSubmitting = false
        currentBurnRequest = nil
        #if canImport(StripeApplePay) && canImport(PassKit)
        currentClientSecret = nil
        applePayContext = nil
        #endif
    }

    private var burnAmountDecimal: Decimal? {
        let raw = burnAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))
    }

    private var burnAmountCents: Int? {
        guard let burnAmountDecimal, burnAmountDecimal > 0 else { return nil }
        let centsDecimal = burnAmountDecimal * Decimal(100)
        let cents = NSDecimalNumber(decimal: centsDecimal).intValue
        return cents > 0 ? cents : nil
    }
}

#if canImport(StripeApplePay) && canImport(PassKit)
extension AltarViewModel: ApplePayContextDelegate {
    func applePayContext(
        _ context: STPApplePayContext,
        didCreatePaymentMethod paymentMethod: StripeAPI.PaymentMethod,
        paymentInformation: PKPayment
    ) async throws -> String {
        guard let currentClientSecret else {
            throw AnkyError.api("The Apple Pay session expired.")
        }

        return currentClientSecret
    }

    func applePayContext(
        _ context: STPApplePayContext,
        didCompleteWith status: STPApplePayContext.PaymentStatus,
        error: Error?
    ) {
        switch status {
        case .success:
            guard let request = currentBurnRequest else {
                resetPaymentState()
                errorMessage = "Apple Pay completed, but the burn couldn't be recorded."
                return
            }

            Task {
                await finalizeBurn(afterSuccessfulApplePay: request)
            }
        case .error:
            resetPaymentState()
            errorMessage = error?.localizedDescription ?? "Apple Pay failed."
        case .userCancellation:
            resetPaymentState()
        @unknown default:
            resetPaymentState()
        }
    }
}
#endif

struct AltarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AltarViewModel()

    var isRootExperience = false

    private let gold = Color(hex: "E8B84B")
    private let generatedBackgroundURL = URL(string: "https://storage.anky.app/stories/8e3499f2-e7ef-44a4-bf12-8a829ed0ac18/page-0.webp")

    var body: some View {
        ZStack(alignment: .topTrailing) {
            altarBackground

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    totalBurned
                    burnControls
                    leaderboardSection
                    recentBurnsSection
                }
                .padding(.horizontal, 22)
                .padding(.top, 72)
                .padding(.bottom, isRootExperience ? 170 : 40)
            }

            if !isRootExperience {
                closeButton
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .onChange(of: viewModel.burnAmountText) { _, _ in
            viewModel.sanitizeAmountInput()
        }
    }

    private var altarBackground: some View {
        ZStack {
            Color(hex: "04040D")
                .ignoresSafeArea()

            if let generatedBackgroundURL {
                AsyncImage(url: generatedBackgroundURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .ignoresSafeArea()
                    default:
                        EmptyView()
                    }
                }
            }

            LinearGradient(
                colors: [
                    Color(hex: "04040D").opacity(0.15),
                    Color(hex: "04040D").opacity(0.55),
                    Color(hex: "04040D").opacity(0.92),
                    Color(hex: "04040D")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    gold.opacity(0.16),
                    Color.clear
                ],
                center: .top,
                startRadius: 60,
                endRadius: 420
            )
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("altar")
                .font(.system(size: 34, weight: .bold, design: .serif))
                .foregroundStyle(gold)

            Text("offer to the fire.")
                .font(.system(size: 14, weight: .medium, design: .serif))
                .foregroundStyle(Color.white.opacity(0.42))
        }
    }

    private var altarImage: some View {
        Group {
            if let url = viewModel.altar?.remoteImageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        Image("anky-face")
                            .resizable()
                            .scaledToFit()
                    case .empty:
                        ProgressView()
                            .tint(gold)
                            .frame(maxWidth: .infinity, minHeight: 220)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image("anky-face")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .padding(.horizontal, 8)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(gold.opacity(0.16), lineWidth: 0.8)
        )
        .shadow(color: gold.opacity(viewModel.imageGlowBoost ? 0.62 : 0.2), radius: viewModel.imageGlowBoost ? 52 : 18)
        .shadow(color: gold.opacity(viewModel.imageGlowBoost ? 0.32 : 0.08), radius: viewModel.imageGlowBoost ? 80 : 28)
    }

    private var totalBurned: some View {
        Text("\(formatUSDC(viewModel.altar?.totalBurnedUsdc ?? 0)) burned")
            .font(.system(size: 36, weight: .bold, design: .serif))
            .foregroundStyle(gold)
            .minimumScaleFactor(0.8)
    }

    private var burnControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("$")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(gold)

                TextField("0.00", text: $viewModel.burnAmountText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(gold)
            }
            .padding(.horizontal, 18)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(gold.opacity(0.18), lineWidth: 0.8)
                    )
            )

            Button {
                viewModel.beginBurn(using: appState)
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isSubmitting {
                        ProgressView()
                            .tint(Color(hex: "04040D"))
                    } else {
                        Text("BURN")
                            .font(.system(size: 18, weight: .bold, design: .serif))
                    }
                    Spacer()
                }
                .frame(height: 58)
                .foregroundStyle(Color(hex: "04040D"))
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(viewModel.canBeginBurn ? gold : gold.opacity(0.38))
                )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canBeginBurn)

            if viewModel.hasPendingBurnSync {
                Button {
                    viewModel.retryPendingBurnSync()
                } label: {
                    Text("retry burn sync")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(gold.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
            }

            if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.56))
            }
        }
    }

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("leaderboard")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundStyle(Color.white.opacity(0.82))

            if let burners = viewModel.altar?.topBurners, !burners.isEmpty {
                VStack(spacing: 10) {
                    ForEach(Array(burners.enumerated()), id: \.element.id) { index, burner in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(gold.opacity(0.9))
                                .frame(width: 20, alignment: .leading)

                            Text(burner.displayName)
                                .font(.system(size: 16, weight: .medium, design: .serif))
                                .foregroundStyle(Color.white.opacity(0.78))

                            Spacer()

                            Text(formatUSDC(burner.totalUsdc))
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.48))
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.035))
                        )
                    }
                }
            } else {
                Text("No burns yet.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.36))
            }
        }
    }

    private var recentBurnsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("recent burns")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundStyle(Color.white.opacity(0.82))

            if let recentBurns = viewModel.altar?.recentBurns, !recentBurns.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(recentBurns) { burn in
                        Text("\(burn.displayName) burned \(formatUSDC(burn.amountUsdc)) — \(relativeTime(for: burn.createdAt))")
                            .font(.system(size: 13, weight: .medium, design: .serif))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
            } else {
                Text("The fire is waiting.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.36))
            }
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.72))
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 18)
        .padding(.trailing, 18)
    }

    private func formatUSDC(_ minorUnits: Int) -> String {
        let amount = NSDecimalNumber(value: Double(minorUnits) / 1_000_000)
        return Self.currencyFormatter.string(from: amount) ?? "$0.00"
    }

    private func relativeTime(for iso8601: String) -> String {
        guard let date = Self.iso8601Formatter.date(from: iso8601)
            ?? Self.fallbackISO8601Formatter.date(from: iso8601) else {
            return "just now"
        }

        return Self.relativeFormatter.localizedString(for: date, relativeTo: .now)
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

private enum PendingBurnSyncStore {
    private static let key = "anky.altar.pending-burn-sync"

    static func load() -> RecordApplePayBurnRequest? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(RecordApplePayBurnRequest.self, from: data)
    }

    static func save(_ request: RecordApplePayBurnRequest) {
        guard let data = try? JSONEncoder().encode(request) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

private extension UIApplication {
    func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let root = base ?? connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController

        if let navigation = root as? UINavigationController {
            return topViewController(base: navigation.visibleViewController)
        }

        if let tab = root as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }

        if let presented = root?.presentedViewController {
            return topViewController(base: presented)
        }

        return root
    }
}
