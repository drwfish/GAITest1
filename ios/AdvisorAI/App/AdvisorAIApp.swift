import SwiftUI

@main
struct AdvisorAIApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
                .tint(Theme.Color.accent)
        }
    }
}
