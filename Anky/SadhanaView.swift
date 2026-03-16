//
//  SadhanaView.swift
//  Anky
//

import SwiftUI

struct SadhanaView: View {
    @Environment(AppState.self) private var appState

    @State private var commitments: [SadhanaCommitment] = []
    @State private var isLoading = false
    @State private var showCreateSheet = false
    @State private var checkedInToday = Set<String>()
    @State private var selectedCommitment: SelectedCommitment?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                Spacer(minLength: 84)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sadhana")
                            .font(.custom("Righteous-Regular", size: 34))
                            .foregroundStyle(Color.ankyGold)

                        Text("No guilt. No gold stars. Just the mirror of whether you showed up.")
                            .font(.custom("Georgia", size: 18))
                            .foregroundStyle(Color.ankyInk.opacity(0.86))
                            .lineSpacing(6)
                    }

                    Spacer()

                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.ankyBlack)
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(Color.ankyGold))
                    }
                    .buttonStyle(.plain)
                }

                if isLoading && commitments.isEmpty {
                    ProgressView()
                        .tint(Color.ankyGold)
                } else if commitments.isEmpty {
                    emptyState
                } else {
                    ForEach(commitments) { commitment in
                        commitmentCard(commitment)
                    }
                }

                Spacer(minLength: 110)
            }
            .padding(.horizontal, 20)
        }
        .background(LinearGradient.ankyBackground.ignoresSafeArea())
        .sheet(isPresented: $showCreateSheet) {
            CreateCommitmentSheet { request in
                Task {
                    await createCommitment(request)
                }
            }
            .presentationDetents([.fraction(0.72)])
            .presentationBackground(Color.ankyBlack)
        }
        .sheet(item: $selectedCommitment) { selection in
            SadhanaDetailSheet(commitmentID: selection.id)
                .presentationDetents([.fraction(0.7), .fraction(0.96)])
                .presentationBackground(Color.ankyBlack)
        }
        .task {
            await loadCommitments()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What will you commit to?")
                .font(.custom("Righteous-Regular", size: 24))
                .foregroundStyle(Color.ankyGold)

            Text("Create one daily or weekly practice. Missing a day is data, not failure.")
                .font(.custom("Georgia", size: 17))
                .foregroundStyle(Color.ankyMuted)
                .lineSpacing(6)

            Button {
                showCreateSheet = true
            } label: {
                Text("Create a commitment")
                    .font(.custom("Righteous-Regular", size: 16))
                    .foregroundStyle(Color.ankyBlack)
                    .padding(.horizontal, 18)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.ankyGold)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .background(cardBackground)
    }

    private func commitmentCard(_ commitment: SadhanaCommitment) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(commitment.title)
                    .font(.custom("Righteous-Regular", size: 22))
                    .foregroundStyle(Color.ankyInk)

                Spacer()

                Button("View") {
                    selectedCommitment = SelectedCommitment(id: commitment.id)
                }
                .font(.custom("Righteous-Regular", size: 12))
                .foregroundStyle(Color.ankyGold)
            }

            if let description = commitment.description, !description.isEmpty {
                Text(description)
                    .font(.custom("Georgia", size: 16))
                    .foregroundStyle(Color.ankyMuted)
                    .lineSpacing(5)
            }

            ProgressView(
                value: Double(commitment.completedCheckins),
                total: Double(max(commitment.targetDays, 1))
            )
            .tint(Color.ankyGold)

            HStack(spacing: 12) {
                SadhanaMetric(title: "Progress", value: "\(commitment.completedCheckins) / \(commitment.targetDays)")
                SadhanaMetric(title: "Frequency", value: commitment.frequency.capitalized)
                SadhanaMetric(title: "Minutes", value: "\(commitment.durationMinutes)")
            }

            HStack(spacing: 10) {
                Button {
                    Task {
                        await checkIn(commitmentID: commitment.id, completed: true)
                    }
                } label: {
                    Text("Did it")
                        .font(.custom("Righteous-Regular", size: 15))
                        .foregroundStyle(Color.ankyBlack)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.ankyGold)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        await checkIn(commitmentID: commitment.id, completed: false)
                    }
                } label: {
                    Text("Not today")
                        .font(.custom("Righteous-Regular", size: 15))
                        .foregroundStyle(Color.ankyMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.ankyPanel)
                        )
                }
                .buttonStyle(.plain)
            }

            if checkedInToday.contains(commitment.id) {
                Text("Today has been acknowledged.")
                    .font(.custom("Georgia", size: 14))
                    .foregroundStyle(Color.ankyMuted)
            }
        }
        .padding(22)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(Color.ankyPanelRaised.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.ankyGold.opacity(0.12), lineWidth: 1)
            )
    }

    private func loadCommitments() async {
        guard appState.isAuthenticated else { return }
        isLoading = true
        defer { isLoading = false }
        commitments = (try? await AnkyAPI.shared.sadhanaCommitments()) ?? []
    }

    private func createCommitment(_ request: SadhanaCommitmentRequest) async {
        guard appState.isAuthenticated else { return }
        if let commitment = try? await AnkyAPI.shared.createSadhana(request) {
            commitments.insert(commitment, at: 0)
            showCreateSheet = false
        }
    }

    private func checkIn(commitmentID: String, completed: Bool) async {
        guard appState.isAuthenticated else { return }

        let request = SadhanaCheckinRequest(completed: completed, notes: nil, date: nil)

        do {
            _ = try await AnkyAPI.shared.checkInSadhana(id: commitmentID, request: request)
            checkedInToday.insert(commitmentID)
            if let index = commitments.firstIndex(where: { $0.id == commitmentID }) {
                let updated = SadhanaCommitment(
                    id: commitments[index].id,
                    title: commitments[index].title,
                    description: commitments[index].description,
                    frequency: commitments[index].frequency,
                    durationMinutes: commitments[index].durationMinutes,
                    targetDays: commitments[index].targetDays,
                    startDate: commitments[index].startDate,
                    isActive: commitments[index].isActive,
                    createdAt: commitments[index].createdAt,
                    totalCheckins: commitments[index].totalCheckins + 1,
                    completedCheckins: commitments[index].completedCheckins + (completed ? 1 : 0)
                )
                commitments[index] = updated
            }
        } catch let error as AnkyError where error.isConnectivityIssue {
            if let bodyData = try? JSONEncoder().encode(request) {
                let action = PendingAction(method: .post, path: "/sadhana/\(commitmentID)/checkin", bodyData: bodyData)
                await OfflineQueue.shared.enqueue(action)
                appState.syncMessage = "check-in saved locally"
                checkedInToday.insert(commitmentID)
            }
        } catch {
            appState.syncMessage = error.localizedDescription
        }
    }
}

private struct SelectedCommitment: Identifiable {
    let id: String
}

private struct SadhanaMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.custom("Righteous-Regular", size: 18))
                .foregroundStyle(Color.ankyGold)

            Text(title.uppercased())
                .font(.custom("Righteous-Regular", size: 10))
                .foregroundStyle(Color.ankyMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.ankyPanel.opacity(0.95))
        )
    }
}

private struct CreateCommitmentSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var frequency = "daily"
    @State private var durationMinutes = 10
    @State private var targetDays = 30

    let onCreate: (SadhanaCommitmentRequest) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Commitment") {
                    TextField("Meditate for 10 minutes", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                }

                Section("Cadence") {
                    Picker("Frequency", selection: $frequency) {
                        Text("Daily").tag("daily")
                        Text("Weekly").tag("weekly")
                    }

                    Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 1...120)
                    Stepper("Target: \(targetDays) days", value: $targetDays, in: 1...365)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ankyBlack)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("New Commitment")
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
                    Button("Create") {
                        onCreate(
                            SadhanaCommitmentRequest(
                                title: title,
                                description: description.isEmpty ? nil : description,
                                frequency: frequency,
                                durationMinutes: durationMinutes,
                                targetDays: targetDays
                            )
                        )
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundStyle(Color.ankyGold)
                }
            }
        }
        .presentationBackground(Color.ankyBlack)
    }
}

#Preview {
    SadhanaView()
        .environment(AppState())
}

private struct SadhanaDetailSheet: View {
    let commitmentID: String

    @State private var detail: SadhanaDetail?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if let detail {
                        Text(detail.title)
                            .font(.custom("Righteous-Regular", size: 28))
                            .foregroundStyle(Color.ankyGold)

                        if let description = detail.description, !description.isEmpty {
                            Text(description)
                                .font(.custom("Georgia", size: 17))
                                .foregroundStyle(Color.ankyInk.opacity(0.88))
                                .lineSpacing(6)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Mirror")
                                .font(.custom("Righteous-Regular", size: 14))
                                .foregroundStyle(Color.ankyMuted)

                            SadhanaHeatmap(
                                startDateString: detail.startDate,
                                targetDays: detail.targetDays,
                                checkins: detail.checkins
                            )
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Check-ins")
                                .font(.custom("Righteous-Regular", size: 14))
                                .foregroundStyle(Color.ankyMuted)

                            ForEach(detail.checkins) { checkin in
                                HStack {
                                    Circle()
                                        .fill(checkin.completed ? Color.ankyGold : Color.ankyPanel)
                                        .frame(width: 12, height: 12)

                                    Text(checkin.date)
                                        .font(.custom("Georgia", size: 16))
                                        .foregroundStyle(Color.ankyInk.opacity(0.88))

                                    Spacer()

                                    Text(checkin.completed ? "Completed" : "Missed")
                                        .font(.custom("Righteous-Regular", size: 12))
                                        .foregroundStyle(checkin.completed ? Color.ankyGold : Color.ankyMuted)
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color.ankyPanelRaised.opacity(0.92))
                                )
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.ankyBlack.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Commitment")
                        .font(.custom("Righteous-Regular", size: 18))
                        .foregroundStyle(Color.ankyInk)
                }
            }
        }
        .presentationBackground(Color.ankyBlack)
        .task {
            detail = try? await AnkyAPI.shared.sadhanaDetail(id: commitmentID)
        }
    }
}

private struct SadhanaHeatmap: View {
    let startDateString: String
    let targetDays: Int
    let checkins: [SadhanaCheckin]

    private let columns = Array(repeating: GridItem(.flexible(minimum: 18), spacing: 8), count: 7)

    var body: some View {
        let dates = timelineDates()
        let lookup = Dictionary(uniqueKeysWithValues: checkins.map { ($0.date, $0.completed) })

        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(dates, id: \.self) { date in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color(for: date, lookup: lookup))
                    .frame(height: 18)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.ankyPanelRaised.opacity(0.92))
        )
    }

    private func timelineDates() -> [String] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        let start = formatter.date(from: startDateString) ?? .now
        return (0..<targetDays).compactMap { offset in
            Calendar(identifier: .gregorian).date(byAdding: .day, value: offset, to: start)
        }
        .map { formatter.string(from: $0) }
    }

    private func color(for date: String, lookup: [String: Bool]) -> Color {
        guard let completed = lookup[date] else { return Color.ankyPanel }
        return completed ? Color.ankyGold : Color.ankyPanelRaised
    }
}
