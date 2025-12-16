import SwiftUI

@main
struct PingMeApp: App {
    @State private var routingViewModel = RoutingViewModel()
    
    init() {
        // Suppress haptic feedback errors (system-level warnings that don't affect functionality)
        // These errors occur when iOS tries to access haptic pattern library that doesn't exist
        // They are harmless and can be safely ignored
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.routingViewModel, routingViewModel)
                .preferredColorScheme(.light) // Force light mode, ignore system dark mode
        }
    }
}
