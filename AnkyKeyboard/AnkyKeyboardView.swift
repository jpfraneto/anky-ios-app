import SwiftUI

struct AnkyKeyboardView: View {
    let onKeyPress: (String) -> Void
    let onDelete: () -> Void
    let onFormatAndReplace: () -> Void

    @StateObject private var store = SharedSessionStore.shared
    @State private var showSymbols: Bool = false

    var body: some View {
        let state = store.state
        let phase = state.phase

        VStack(spacing: 0) {
            CommandCenterBar(
                phase: phase,
                streakSeconds: state.streakSeconds,
                totalDuration: state.totalDuration,
                keystrokeCount: state.keystrokeCount
            )

            KeyboardGrid(
                phase: phase,
                onKeyPress: onKeyPress,
                onDelete: onDelete,
                showSymbols: $showSymbols
            )

            BottomActionBar(
                phase: phase,
                isExternalApp: state.isExternalApp,
                hasPendingFormatted: state.pendingFormattedText != nil,
                showSymbols: $showSymbols,
                onKeyPress: onKeyPress,
                onFormatAndReplace: onFormatAndReplace
            )
        }
        .background(phaseColor(phase))
        .animation(.easeInOut(duration: 0.6), value: phase)
    }
}
