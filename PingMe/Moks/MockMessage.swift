import Foundation

// MARK: - Mock Message (Legacy - not used anymore)
struct MockMessage: Identifiable {
    let id = UUID()
    let content: String
    let timestamp: Date
    let isFromCurrentUser: Bool
}
