//
//  ServerIndicator.swift
//  Anky
//

import Combine
import SwiftUI

struct ServerIndicator: View {
    @State private var isReachable: Bool? = nil
    @State private var lastCheckedAt: Date? = nil

    private var environmentLabel: String {
        #if DEBUG
        return "staging"
        #else
        return "prod"
        #endif
    }

    private var dotColor: Color {
        guard let isReachable else { return Color.gray.opacity(0.3) }
        return isReachable
            ? Color(red: 0.70, green: 0.40, blue: 1.0)
            : Color(red: 0.8, green: 0.3, blue: 0.3)
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .shadow(color: dotColor.opacity(0.6), radius: isReachable == true ? 3 : 0)

            #if DEBUG
            Text(environmentLabel)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.35))
            #endif
        }
        .task {
            await checkReachability()
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            Task { await checkReachability() }
        }
    }

    private func checkReachability() async {
        let url = AnkyAPI.shared.baseURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                await MainActor.run {
                    self.isReachable = (200..<500).contains(http.statusCode)
                    self.lastCheckedAt = Date()
                }
            }
        } catch {
            await MainActor.run {
                self.isReachable = false
                self.lastCheckedAt = Date()
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        ServerIndicator()
    }
}
