import SwiftUI

@main
struct AnkyApp: App {
    @State private var appState = AppState()

    init() {
        AnkyAudioSession.configureIfNeeded()
        FontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
    }
}
