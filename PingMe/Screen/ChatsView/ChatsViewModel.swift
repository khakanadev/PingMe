import Foundation
import Observation

extension Notification.Name {
    static let userDataUpdated = Notification.Name("userDataUpdated")
}

// MARK: - View Model
@Observable
class ChatsViewModel {
    var chats: [Chat] = []
    var stories: [Story] = []
    var currentUser: Story?
    var isSlideBarShowing: Bool = false
    var isEditProfileActive: Bool = false
    var currentUserName: String = "Имя пользователя"
    var username: String = "username"
    var avatarUrl: String?

    // MARK: - Initialization
    init() {
        loadUserData()
        setupMockData()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadUserData),
            name: .userDataUpdated,
            object: nil
        )
    }

    // MARK: - Mock Data Setup
    private func setupMockData() {
        if currentUser == nil {
            currentUser = Story(username: currentUserName, avatarUrl: nil)
        }

        stories = [
            Story(username: "Name", avatarUrl: nil),
            Story(username: "Name", avatarUrl: nil),
            Story(username: "Name", avatarUrl: nil),
            Story(username: "Name", avatarUrl: nil),
            Story(username: "Name", avatarUrl: nil),
            Story(username: "Name", avatarUrl: nil),
        ]

        chats = [
            Chat(
                username: "Name", lastMessage: "last message...",
                lastMessageTime: Date(timeIntervalSinceNow: -120)),
            Chat(
                username: "Group name", lastMessage: "last message...",
                lastMessageTime: Date(timeIntervalSinceNow: -240)),
            Chat(
                username: "Name", lastMessage: "last message...",
                lastMessageTime: Date(timeIntervalSinceNow: -7200), isGroup: true),
            Chat(
                username: "Group name", lastMessage: "last message...",
                lastMessageTime: Date(timeIntervalSinceNow: -14400), isGroup: true),
            Chat(
                username: "Name", lastMessage: "last message...",
                lastMessageTime: Date(timeIntervalSinceNow: -21600)),
            Chat(
                username: "Name", lastMessage: "last message...",
                lastMessageTime: Date(timeIntervalSinceNow: -36000)),
            Chat(
                username: "Group name", lastMessage: "last message...",
                lastMessageTime: Date(timeIntervalSinceNow: -43200), isGroup: true),
            Chat(
                username: "Name", lastMessage: "last message...",
                lastMessageTime: Date(timeIntervalSinceNow: -36000)),
            Chat(
                username: "Group name", lastMessage: "last message...",
                lastMessageTime: Date(timeIntervalSinceNow: -43200), isGroup: true),
            Chat(
                username: "Name", lastMessage: "last message...",
                lastMessageTime: Date(timeIntervalSinceNow: -36000)),
            Chat(
                username: "Group name", lastMessage: "last message...",
                lastMessageTime: Date(timeIntervalSinceNow: -43200), isGroup: true),
            Chat(
                username: "Name", lastMessage: "last message...",
                lastMessageTime: Date(timeIntervalSinceNow: -36000)),
            Chat(
                username: "Group name", lastMessage: "last message...",
                lastMessageTime: Date(timeIntervalSinceNow: -43200), isGroup: true),
        ]
    }

    // MARK: - User Data Loading
    private func loadUserData() {
        guard let data = UserDefaults.standard.data(forKey: "userData") else { return }

        do {
            let user = try JSONDecoder().decode(User.self, from: data)
            currentUserName = user.name
            username = user.username ?? user.name
            avatarUrl = user.avatarUrl
            currentUser = Story(username: username, avatarUrl: user.avatarUrl)
        } catch {
            print("Failed to decode user data: \(error)")
        }
    }

    @objc
    private func reloadUserData() {
        loadUserData()
    }
}
