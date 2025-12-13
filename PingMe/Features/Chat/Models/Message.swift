import Foundation

// MARK: - Message Model
struct Message: Codable, Identifiable {
    let id: UUID
    let content: String
    let senderId: UUID
    let sender: User?
    let conversationId: UUID
    let forwardedFromId: UUID?
    let media: [MessageMedia]
    let createdAt: Date
    let updatedAt: Date
    let isEdited: Bool
    let isDeleted: Bool
    
    // Computed property for backward compatibility
    var senderName: String {
        sender?.name ?? "Unknown"
    }

    enum CodingKeys: String, CodingKey {
        case id, content
        case senderId = "sender_id"
        case sender
        case conversationId = "conversation_id"
        case forwardedFromId = "forwarded_from_id"
        case media
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isEdited = "is_edited"
        case isDeleted = "is_deleted"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        senderId = try container.decode(UUID.self, forKey: .senderId)
        sender = try container.decodeIfPresent(User.self, forKey: .sender)
        conversationId = try container.decode(UUID.self, forKey: .conversationId)
        forwardedFromId = try container.decodeIfPresent(UUID.self, forKey: .forwardedFromId)
        media = try container.decodeIfPresent([MessageMedia].self, forKey: .media) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isEdited = try container.decodeIfPresent(Bool.self, forKey: .isEdited) ?? false
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
    }
    
    // MARK: - Manual Initializer
    init(
        id: UUID,
        content: String,
        senderId: UUID,
        sender: User?,
        conversationId: UUID,
        forwardedFromId: UUID?,
        media: [MessageMedia],
        createdAt: Date,
        updatedAt: Date,
        isEdited: Bool,
        isDeleted: Bool
    ) {
        self.id = id
        self.content = content
        self.senderId = senderId
        self.sender = sender
        self.conversationId = conversationId
        self.forwardedFromId = forwardedFromId
        self.media = media
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isEdited = isEdited
        self.isDeleted = isDeleted
    }
}

// MARK: - Message Media
struct MessageMedia: Codable, Identifiable {
    let id: UUID
    let contentType: String
    let url: String
    let size: Int
    let messageId: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case contentType = "content_type"
        case url, size
        case messageId = "message_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Message Display Model (for UI)
struct MessageDisplay: Identifiable {
    let id: UUID
    let content: String
    let timestamp: Date
    let isFromCurrentUser: Bool
    let senderName: String
    let isEdited: Bool
    let isDeleted: Bool
    let media: [MessageMedia]
    
    init(from message: Message, currentUserId: UUID, recipientId: UUID? = nil) {
        self.id = message.id
        self.content = message.content
        self.timestamp = message.createdAt
        
        // Simple logic: message is from current user if senderId matches currentUserId
        // Messages from current user → right side
        // Messages from recipient → left side
        self.isFromCurrentUser = message.senderId == currentUserId
        
        self.senderName = message.senderName
        self.isEdited = message.isEdited
        self.isDeleted = message.isDeleted
        self.media = message.media
    }
}

// MARK: - Send Message Request
struct SendMessageRequest: Codable {
    let conversationId: UUID
    let content: String
    let forwardedFromId: UUID?
    let mediaIds: [UUID]?

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case content
        case forwardedFromId = "forwarded_from_id"
        case mediaIds = "media_ids"
    }
}

