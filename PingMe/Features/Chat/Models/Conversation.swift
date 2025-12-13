import Foundation

// MARK: - Conversation Type
enum ConversationType: String, Codable {
    case dialog = "dialog"
    case polylogue = "polylogue"
}

// MARK: - Conversation Model
struct Conversation: Codable, Identifiable {
    let id: UUID
    let name: String?
    let conversationType: ConversationType
    let participants: [ConversationParticipant]?
    let lastMessage: Message?
    let lastReadMessageId: UUID?
    let createdAt: Date
    let updatedAt: Date
    let isDeleted: Bool
    let deletedAt: Date?
    let avatarUrl: String?
    
    // Computed property for backward compatibility
    var isGroup: Bool {
        conversationType == .polylogue
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case conversationType = "conversation_type"
        case participants
        case lastMessage = "last_message"
        case lastReadMessageId = "last_read_message_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isDeleted = "is_deleted"
        case deletedAt = "deleted_at"
        case avatarUrl = "avatar_url"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        conversationType = try container.decode(ConversationType.self, forKey: .conversationType)
        
        // These fields may not be present in ConversationResponse (only in detailed responses)
        participants = try container.decodeIfPresent([ConversationParticipant].self, forKey: .participants)
        lastMessage = try container.decodeIfPresent(Message.self, forKey: .lastMessage)
        lastReadMessageId = try container.decodeIfPresent(UUID.self, forKey: .lastReadMessageId)
        
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
    }
    
    // MARK: - Manual Initializer
    init(
        id: UUID,
        name: String?,
        conversationType: ConversationType,
        participants: [ConversationParticipant]?,
        lastMessage: Message?,
        lastReadMessageId: UUID?,
        createdAt: Date,
        updatedAt: Date,
        isDeleted: Bool,
        deletedAt: Date?,
        avatarUrl: String?
    ) {
        self.id = id
        self.name = name
        self.conversationType = conversationType
        self.participants = participants
        self.lastMessage = lastMessage
        self.lastReadMessageId = lastReadMessageId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
        self.avatarUrl = avatarUrl
    }
}

// MARK: - Conversation Participant
struct ConversationParticipant: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let userName: String
    let userAvatarUrl: String?
    let isOnline: Bool
    let joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case userName = "user_name"
        case userAvatarUrl = "user_avatar_url"
        case isOnline = "is_online"
        case joinedAt = "joined_at"
    }
}

// MARK: - Create Conversation Request
struct CreateConversationRequest: Codable {
    let participantIds: [UUID]?
    let name: String?  // Can be null according to API, but required field

    enum CodingKeys: String, CodingKey {
        case participantIds = "participant_ids"
        case name
    }
    
    init(participantIds: [UUID]?, name: String? = nil) {
        self.participantIds = participantIds
        // API requires name field, but it can be null or empty string
        // We'll send empty string if nil to satisfy the requirement
        self.name = name ?? ""
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(participantIds, forKey: .participantIds)
        // Always encode name (even if empty string) as it's required by API
        try container.encode(name ?? "", forKey: .name)
    }
}

