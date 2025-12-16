import Foundation

struct UserBrief: Codable, Identifiable {
    let id: UUID
    let name: String
    let username: String?
    let isOnline: Bool
    let lastSeen: Date?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name, username
        case isOnline = "is_online"
        case lastSeen = "last_seen"
        case avatarUrl = "avatar_url"
    }
    
    init(id: UUID, name: String, username: String?, isOnline: Bool, lastSeen: Date?, avatarUrl: String?) {
        self.id = id
        self.name = name
        self.username = username
        self.isOnline = isOnline
        self.lastSeen = lastSeen
        self.avatarUrl = avatarUrl
    }
}
