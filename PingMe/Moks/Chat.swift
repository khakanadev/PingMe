import Foundation

struct Chat: Identifiable {
    let id: UUID
    let username: String
    let lastMessage: String
    let lastMessageTime: Date
    let avatarUrl: String?
    let isGroup: Bool
    let hasUnreadMessages: Bool // Indicates if there are unread messages

    init(
        id: UUID = UUID(), username: String, lastMessage: String, lastMessageTime: Date,
        avatarUrl: String? = nil, isGroup: Bool = false, hasUnreadMessages: Bool = false
    ) {
        self.id = id
        self.username = username
        self.lastMessage = lastMessage
        self.lastMessageTime = lastMessageTime
        self.avatarUrl = avatarUrl
        self.isGroup = isGroup
        self.hasUnreadMessages = hasUnreadMessages
    }
}
