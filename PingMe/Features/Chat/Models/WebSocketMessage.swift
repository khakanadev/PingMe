import Foundation

// MARK: - WebSocket Message Types
enum WebSocketMessageType: String, Codable {
    // Client → Server
    case auth
    case message
    case messageEdit = "message_edit"
    case messageDelete = "message_delete"
    case messageForward = "message_forward"
    case typingStart = "typing_start"
    case typingStop = "typing_stop"
    case markRead = "mark_read"
    case subscribe
    case unsubscribe
    case ack
    case ping
    
    // Server → Client
    case authSuccess = "auth_success"
    case messageAck = "message_ack"
    case markReadSuccess = "mark_read_success"
    case messageRead = "message_read"
    case userOnline = "user_online"
    case userOffline = "user_offline"
    case pong
    case error
}

// MARK: - WebSocket Outgoing Message (Client → Server)
struct WebSocketOutgoingMessage: Codable {
    let type: WebSocketMessageType
    
    // Auth
    var token: String?
    
    // Message
    var conversationId: UUID?
    var content: String?
    var forwardedFromId: UUID?
    var mediaIds: [UUID]?
    
    // Message Edit/Delete/Forward
    var messageId: UUID?
    
    // Typing
    // conversationId already defined above
    
    // Mark Read
    // messageId and conversationId already defined above
    
    // Subscribe/Unsubscribe
    // conversationId already defined above
    
    // ACK
    var sequence: Int?
    
    enum CodingKeys: String, CodingKey {
        case type, token
        case conversationId = "conversation_id"
        case content
        case forwardedFromId = "forwarded_from_id"
        case mediaIds = "media_ids"
        case messageId = "message_id"
        case sequence
    }
}

// MARK: - WebSocket Incoming Message (Server → Client)
struct WebSocketIncomingMessage: Codable {
    let type: WebSocketMessageType
    let sequence: Int?
    
    // Auth Success
    var userId: UUID?
    var userName: String?
    
    // Message
    var id: UUID?
    var content: String?
    var senderId: UUID?
    var senderName: String?
    var conversationId: UUID?
    var forwardedFromId: UUID?
    var media: [MessageMedia]?
    var createdAt: String?
    var updatedAt: String?
    var isEdited: Bool?
    var isDeleted: Bool?
    
    // Message Edit/Delete/Forward
    var messageId: UUID?
    var deletedAt: String?
    var originalMessageId: UUID?
    var newMessageId: UUID?
    
    // Typing (uses userId and userName from auth success)
    
    // Mark Read
    var readerId: UUID?
    var readerName: String?
    
    // User Status
    var lastSeen: String?
    
    // Message ACK
    var status: String?
    
    // Error
    var code: String?
    var message: String?
    var details: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case type, sequence
        case userId = "user_id"
        case userName = "user_name"
        case id, content
        case senderId = "sender_id"
        case senderName = "sender_name"
        case conversationId = "conversation_id"
        case forwardedFromId = "forwarded_from_id"
        case media
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isEdited = "is_edited"
        case isDeleted = "is_deleted"
        case messageId = "message_id"
        case deletedAt = "deleted_at"
        case originalMessageId = "original_message_id"
        case newMessageId = "new_message_id"
        case readerId = "reader_id"
        case readerName = "reader_name"
        case lastSeen = "last_seen"
        case status, code, message, details
    }
}

