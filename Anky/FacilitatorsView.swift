import SwiftUI

struct FacilitatorsView: View {
    @Environment(AppState.self) private var appState

    @State private var recommended: [Facilitator] = []
    @State private var all: [Facilitator] = []
    @State private var message: String?
    @State private var isLoading = false
    @State private var selectedFacilitator: SelectedFacilitator?
    @State private var showApplySheet = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header

                if isLoading, recommended.isEmpty, all.isEmpty {
                    ProgressView()
                        .tint(Color.ankyGold)
                } else {
                    if !recommended.isEmpty || message != nil {
                        sectionTitle("Recommended")

                        if let message {
                            Text(message)
                                .font(.custom("Georgia", size: 16))
                                .foregroundStyle(Color.ankyMuted)
                                .lineSpacing(5)
                        }

                        ForEach(recommended) { facilitator in
                            facilitatorCard(facilitator, emphasizeMatch: true)
                        }
                    }

                    sectionTitle("All facilitators")

                    ForEach(all) { facilitator in
                        facilitatorCard(facilitator, emphasizeMatch: false)
                    }
                }
            }
            .padding(20)
        }
        .background(Color.ankyBlack.ignoresSafeArea())
        .navigationTitle("Facilitators")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Apply") {
                    showApplySheet = true
                }
                .foregroundStyle(Color.ankyGold)
            }
        }
        .sheet(item: $selectedFacilitator) { selection in
            FacilitatorDetailSheet(facilitatorID: selection.id)
                .presentationDetents([.fraction(0.7), .fraction(0.96)])
                .presentationBackground(Color.ankyBlack)
                .environment(appState)
        }
        .sheet(isPresented: $showApplySheet) {
            FacilitatorApplicationSheet { request in
                Task {
                    await apply(request)
                }
            }
            .presentationDetents([.fraction(0.78), .fraction(0.95)])
            .presentationBackground(Color.ankyBlack)
        }
        .task {
            await load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Human guides for what the words can’t hold alone.")
                .font(.custom("Righteous-Regular", size: 28))
                .foregroundStyle(Color.ankyGold)

            Text("Anky doesn’t compete with humans. It listens long enough to know when a human should step in.")
                .font(.custom("Georgia", size: 17))
                .foregroundStyle(Color.ankyInk.opacity(0.88))
                .lineSpacing(6)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.custom("Righteous-Regular", size: 12))
            .foregroundStyle(Color.ankyMuted)
            .tracking(1.4)
    }

    private func facilitatorCard(_ facilitator: Facilitator, emphasizeMatch: Bool) -> some View {
        Button {
            selectedFacilitator = SelectedFacilitator(id: facilitator.id)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    AsyncAvatar(urlString: facilitator.profileImageUrl, fallback: facilitator.name)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(facilitator.name)
                            .font(.custom("Righteous-Regular", size: 21))
                            .foregroundStyle(Color.ankyInk)

                        HStack(spacing: 10) {
                            Text(String(format: "$%.0f", facilitator.sessionRateUsd))
                            Text(String(format: "%.1f ★", facilitator.avgRating))
                        }
                        .font(.custom("Georgia", size: 15))
                        .foregroundStyle(Color.ankyMuted)
                    }

                    Spacer()
                }

                FlowLayout(items: facilitator.specialties) { specialty in
                    Text(specialty)
                        .font(.custom("Righteous-Regular", size: 11))
                        .foregroundStyle(Color.ankyGold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.ankyPanel.opacity(0.9))
                        )
                }

                Text(facilitator.bio)
                    .font(.custom("Georgia", size: 16))
                    .foregroundStyle(Color.ankyInk.opacity(0.9))
                    .lineSpacing(5)
                    .lineLimit(4)

                if emphasizeMatch, let matchReason = facilitator.matchReason, !matchReason.isEmpty {
                    Text(matchReason)
                        .font(.custom("Georgia-Italic", size: 15))
                        .foregroundStyle(Color.ankyGold.opacity(0.92))
                        .lineSpacing(5)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.ankyPanelRaised.opacity(0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.ankyGold.opacity(0.12), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        async let allTask = try? AnkyAPI.shared.facilitators()
        async let recommendedTask = try? AnkyAPI.shared.recommendedFacilitators()

        all = await allTask ?? []
        if let recommendedResponse = await recommendedTask {
            recommended = recommendedResponse.facilitators
            message = recommendedResponse.message
        } else {
            recommended = []
            message = nil
        }
    }

    private func apply(_ request: FacilitatorApplicationRequest) async {
        _ = try? await AnkyAPI.shared.applyAsFacilitator(request)
        await load()
    }
}

private struct SelectedFacilitator: Identifiable {
    let id: String
}

private struct FacilitatorDetailSheet: View {
    @Environment(AppState.self) private var appState

    let facilitatorID: String

    @State private var detail: FacilitatorDetail?
    @State private var isLoading = false
    @State private var showBooking = false
    @State private var showReview = false
    @State private var confirmation: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if let detail {
                        HStack(alignment: .top, spacing: 16) {
                            AsyncAvatar(urlString: detail.profileImageUrl, fallback: detail.name, size: 72)

                            VStack(alignment: .leading, spacing: 8) {
                                Text(detail.name)
                                    .font(.custom("Righteous-Regular", size: 28))
                                    .foregroundStyle(Color.ankyInk)

                                Text(String(format: "$%.0f/session · %.1f ★", detail.sessionRateUsd, detail.avgRating))
                                    .font(.custom("Georgia", size: 16))
                                    .foregroundStyle(Color.ankyMuted)

                                if let location = detail.location {
                                    Text(location.capitalized)
                                        .font(.custom("Georgia", size: 15))
                                        .foregroundStyle(Color.ankyMuted)
                                }
                            }
                        }

                        if let matchReason = detail.matchReason, !matchReason.isEmpty {
                            Text(matchReason)
                                .font(.custom("Georgia-Italic", size: 16))
                                .foregroundStyle(Color.ankyGold)
                                .lineSpacing(5)
                                .padding(18)
                                .background(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .fill(Color.ankyPanel.opacity(0.92))
                                )
                        }

                        FlowLayout(items: detail.specialties) { specialty in
                            Text(specialty)
                                .font(.custom("Righteous-Regular", size: 11))
                                .foregroundStyle(Color.ankyGold)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.ankyPanel.opacity(0.9))
                                )
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Bio")
                                .font(.custom("Righteous-Regular", size: 14))
                                .foregroundStyle(Color.ankyMuted)

                            Text(detail.bio)
                                .font(.custom("Georgia", size: 17))
                                .foregroundStyle(Color.ankyInk.opacity(0.9))
                                .lineSpacing(6)
                        }

                        if let approach = detail.approach, !approach.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Approach")
                                    .font(.custom("Righteous-Regular", size: 14))
                                    .foregroundStyle(Color.ankyMuted)

                                Text(approach)
                                    .font(.custom("Georgia", size: 17))
                                    .foregroundStyle(Color.ankyInk.opacity(0.9))
                                    .lineSpacing(6)
                            }
                        }

                        HStack(spacing: 12) {
                            Button {
                                showBooking = true
                            } label: {
                                Text("Book")
                                    .font(.custom("Righteous-Regular", size: 17))
                                    .foregroundStyle(Color.ankyBlack)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .fill(Color.ankyGold)
                                    )
                            }
                            .buttonStyle(.plain)

                            Button {
                                showReview = true
                            } label: {
                                Text("Review")
                                    .font(.custom("Righteous-Regular", size: 17))
                                    .foregroundStyle(Color.ankyGold)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .fill(Color.ankyPanelRaised.opacity(0.94))
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        if let confirmation {
                            Text(confirmation)
                                .font(.custom("Georgia", size: 15))
                                .foregroundStyle(Color.ankyGold)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Reviews")
                                .font(.custom("Righteous-Regular", size: 17))
                                .foregroundStyle(Color.ankyInk)

                            if detail.reviews.isEmpty {
                                Text("No reviews yet.")
                                    .font(.custom("Georgia", size: 16))
                                    .foregroundStyle(Color.ankyMuted)
                            } else {
                                ForEach(detail.reviews) { review in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("\(review.rating) ★")
                                            .font(.custom("Righteous-Regular", size: 14))
                                            .foregroundStyle(Color.ankyGold)

                                        if let reviewText = review.reviewText, !reviewText.isEmpty {
                                            Text(reviewText)
                                                .font(.custom("Georgia", size: 16))
                                                .foregroundStyle(Color.ankyInk.opacity(0.88))
                                                .lineSpacing(5)
                                        }

                                        Text(review.createdAt.replacingOccurrences(of: "T", with: " ").prefix(16))
                                            .font(.custom("Georgia", size: 13))
                                            .foregroundStyle(Color.ankyMuted)
                                    }
                                    .padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .fill(Color.ankyPanelRaised.opacity(0.92))
                                    )
                                }
                            }
                        }
                    } else if isLoading {
                        ProgressView()
                            .tint(Color.ankyGold)
                    }
                }
                .padding(20)
            }
            .background(Color.ankyBlack.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Facilitator")
                        .font(.custom("Righteous-Regular", size: 18))
                        .foregroundStyle(Color.ankyInk)
                }
            }
        }
        .sheet(isPresented: $showBooking, onDismiss: {
            Task {
                await load()
            }
        }) {
            FacilitatorBookingSheet(facilitatorID: facilitatorID) { response in
                confirmation = "Booked. \(response.facilitatorName) will reach you through the handoff below."
            }
            .presentationDetents([.fraction(0.62), .fraction(0.9)])
            .presentationBackground(Color.ankyBlack)
            .environment(appState)
        }
        .sheet(isPresented: $showReview, onDismiss: {
            Task {
                await load()
            }
        }) {
            FacilitatorReviewSheet(facilitatorID: facilitatorID)
                .presentationDetents([.fraction(0.52), .fraction(0.82)])
                .presentationBackground(Color.ankyBlack)
                .environment(appState)
        }
        .task {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        detail = try? await AnkyAPI.shared.facilitator(id: facilitatorID)
    }
}

private struct FacilitatorBookingSheet: View {
    @Environment(\.dismiss) private var dismiss

    let facilitatorID: String
    let onBooked: (FacilitatorBookingResponse) -> Void

    @State private var paymentKind = 0
    @State private var reference = ""
    @State private var shareContext = true
    @State private var confirmation: FacilitatorBookingResponse?

    var body: some View {
        NavigationStack {
            Form {
                Section("Payment reference") {
                    Picker("Type", selection: $paymentKind) {
                        Text("Stripe").tag(0)
                        Text("USDC").tag(1)
                    }
                    .pickerStyle(.segmented)

                    TextField(paymentKind == 0 ? "pi_..." : "0x...", text: $reference)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Context") {
                    Toggle("Share anonymized writing context", isOn: $shareContext)
                }

                if let confirmation {
                    Section("Confirmation") {
                        Text("Booking id: \(confirmation.bookingId)")
                        if let bookingURL = confirmation.bookingUrl {
                            Link("Open booking link", destination: URL(string: bookingURL)!)
                        }
                        if let contact = confirmation.contactMethod {
                            Text(contact)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ankyBlack)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Book Session")
                        .font(.custom("Righteous-Regular", size: 18))
                        .foregroundStyle(Color.ankyInk)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Submit") {
                        Task {
                            await submit()
                        }
                    }
                    .disabled(reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundStyle(Color.ankyGold)
                }
            }
        }
        .presentationBackground(Color.ankyBlack)
    }

    private func submit() async {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let request = FacilitatorBookingRequest(
            paymentTxHash: paymentKind == 1 ? trimmed : nil,
            stripePaymentId: paymentKind == 0 ? trimmed : nil,
            shareContext: shareContext
        )

        if let response = try? await AnkyAPI.shared.bookFacilitator(id: facilitatorID, request: request) {
            confirmation = response
            onBooked(response)
            dismiss()
        }
    }
}

private struct FacilitatorReviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let facilitatorID: String

    @State private var rating = 5
    @State private var reviewText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Rating") {
                    Stepper("Rating: \(rating)", value: $rating, in: 1...5)
                }

                Section("Review") {
                    TextField("What did this session make possible?", text: $reviewText, axis: .vertical)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ankyBlack)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Leave Review")
                        .font(.custom("Righteous-Regular", size: 18))
                        .foregroundStyle(Color.ankyInk)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Send") {
                        Task {
                            await submit()
                        }
                    }
                    .foregroundStyle(Color.ankyGold)
                }
            }
        }
        .presentationBackground(Color.ankyBlack)
    }

    private func submit() async {
        let request = FacilitatorReviewRequest(
            rating: rating,
            reviewText: reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : reviewText
        )

        _ = try? await AnkyAPI.shared.reviewFacilitator(id: facilitatorID, request: request)
        dismiss()
    }
}

private struct FacilitatorApplicationSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var websiteURL = ""
    @State private var instagramProfile = ""

    let onSubmit: (FacilitatorApplicationRequest) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Instagram required. Website optional.")
                        .font(.custom("Georgia", size: 15))
                        .foregroundStyle(Color.ankyMuted)

                    TextField("Website (optional)", text: $websiteURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    TextField("Instagram link", text: $instagramProfile)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ankyBlack)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Apply")
                        .font(.custom("Righteous-Regular", size: 18))
                        .foregroundStyle(Color.ankyInk)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Color.ankyMuted)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Send") {
                        guard let request = applicationRequest else { return }
                        onSubmit(request)
                        dismiss()
                    }
                    .disabled(applicationRequest == nil)
                    .foregroundStyle(Color.ankyGold)
                }
            }
        }
        .presentationBackground(Color.ankyBlack)
    }

    private var applicationRequest: FacilitatorApplicationRequest? {
        guard let instagramURL = instagramProfile.normalizedInstagramProfileURL else { return nil }

        let handle = instagramProfile.instagramHandle ?? "instagram"

        // Keep the UI simple and map social inputs onto the current backend contract.
        return FacilitatorApplicationRequest(
            name: "@\(handle)",
            bio: "Instagram: \(instagramURL)",
            specialties: ["instagram"],
            approach: normalizedWebsiteURL.map { "Website: \($0)" },
            sessionRateUsd: 1,
            bookingUrl: normalizedWebsiteURL,
            contactMethod: instagramURL,
            profileImageUrl: nil,
            location: "remote",
            languages: ["en"]
        )
    }

    private var normalizedWebsiteURL: String? {
        websiteURL.normalizedWebURL
    }
}

private struct AsyncAvatar: View {
    let urlString: String?
    let fallback: String
    var size: CGFloat = 56

    var body: some View {
        if let urlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                avatarFallback
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            avatarFallback
        }
    }

    private var avatarFallback: some View {
        ZStack {
            Circle()
                .fill(Color.ankyPanel.opacity(0.95))
            Text(String(fallback.prefix(1)).uppercased())
                .font(.custom("Righteous-Regular", size: size * 0.34))
                .foregroundStyle(Color.ankyGold)
        }
        .frame(width: size, height: size)
    }
}

private struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let items: Data
    let content: (Data.Element) -> Content

    init(items: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(Array(items), id: \.self) { item in
                    content(item)
                }
            }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var csvList: [String] {
        split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var normalizedWebURL: String? {
        guard let value = nilIfBlank else { return nil }
        let candidate = value.hasPrefix("http://") || value.hasPrefix("https://") ? value : "https://\(value)"
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme,
              let host = components.host,
              !scheme.isEmpty,
              !host.isEmpty else {
            return nil
        }
        return components.url?.absoluteString
    }

    var normalizedInstagramProfileURL: String? {
        if let value = normalizedWebURL,
           let components = URLComponents(string: value),
           let host = components.host?.lowercased(),
           host.contains("instagram.com") {
            guard let handle = components.path
                .split(separator: "/")
                .map(String.init)
                .first?
                .trimmingCharacters(in: CharacterSet(charactersIn: "@")),
                  !handle.isEmpty else {
                return nil
            }
            return "https://instagram.com/\(handle)"
        }

        guard let value = nilIfBlank else { return nil }
        let handle = value.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._"))
        guard !handle.isEmpty, handle.unicodeScalars.allSatisfy(allowedCharacters.contains) else {
            return nil
        }
        return "https://instagram.com/\(handle)"
    }

    var instagramHandle: String? {
        guard let normalizedInstagramProfileURL,
              let url = URL(string: normalizedInstagramProfileURL) else {
            return nil
        }

        return url.path
            .split(separator: "/")
            .map(String.init)
            .first
    }
}
