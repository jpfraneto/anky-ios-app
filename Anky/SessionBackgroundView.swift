import SwiftUI

struct SessionBackgroundView: View {
    @StateObject private var store = SharedSessionStore.shared
    @State private var timer: Timer? = nil

    var body: some View {
        ZStack {
            phaseColor(store.state.phase)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.8), value: store.state.phase)

            if store.state.phase == .flow || store.state.phase == .transcendent {
                RadialGradient(
                    colors: [
                        phaseAccentColor(store.state.phase).opacity(0.15),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 300
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 1.2), value: store.state.phase)
            }

            ContentView()
        }
        .onAppear { startPolling() }
        .onDisappear { timer?.invalidate() }
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            let newState = SharedSessionStore.shared.load()
            if newState.phase != store.state.phase ||
               newState.isActive != store.state.isActive {
                store.state = newState
            }
        }
    }
}
