// swiftlint:disable type_body_length cyclomatic_complexity line_length
import Foundation
import Observation
import SwiftUI

extension Notification.Name {
    static let userDataUpdated = Notification.Name("userDataUpdated")
    static let conversationCreated = Notification.Name("conversationCreated")
    static let messageSent = Notification.Name("messageSent")
    static let conversationViewed = Notification.Name("conversationViewed")
}

// MARK: - View Model
@Observable
class ChatsViewModel {
    var chats: [Chat] = []
    var stories: [Story] = []
    var currentUser: Story?
    var isSlideBarShowing: Bool = false
    var isEditProfileActive: Bool = false
    var isSearchUsersActive: Bool = false
    var isUserProfileActive: Bool = false
    var isChatActive: Bool = false
    var selectedUser: UserBrief?
    var selectedChatInfo: ChatInfo?
    var currentUserName: String = "Имя пользователя"
    var username: String = "username"
    var avatarUrl: String?
    var isLoading: Bool = false
    var errorMessage: String?
    
    // MARK: - Cache Management
    private var lastLoadTime: Date?
    private var isDataLoaded: Bool = false
    private let cacheValidityDuration: TimeInterval = 30 // Cache valid for 30 seconds
    
    // MARK: - Chat Info
    struct ChatInfo: Identifiable, Hashable {
        let id: UUID
        let userId: UUID
        let userName: String
        let isOnline: Bool
        let conversationId: UUID?
        
        init(userId: UUID, userName: String, isOnline: Bool, conversationId: UUID?) {
            self.id = UUID() // Unique ID for navigation
            self.userId = userId
            self.userName = userName
            self.isOnline = isOnline
            self.conversationId = conversationId
        }
    }
    
    // MARK: - Services
    private let conversationService = ConversationService()
    private let profileService = ProfileService()
    private var currentUserId: UUID?
    
    // MARK: - Cached Data
    private var conversationMessages: [UUID: [Message]] = [:]
    private var conversationParticipants: [UUID: [ConversationParticipant]] = [:]
    
    // MARK: - Conversation Recipient Mapping
    struct RecipientMeta: Codable, Hashable {
        let userId: UUID
        let userName: String
        let username: String?
        let avatarUrl: String?
        let isOnline: Bool
    }
    
    // Store mapping of conversationId -> recipient data for conversations where all messages are from current user
    private var _conversationRecipientMap: [UUID: RecipientMeta] = [:]
    
    private var conversationRecipientMap: [UUID: RecipientMeta] {
        get { _conversationRecipientMap }
        set {
            _conversationRecipientMap = newValue
            // Persist to UserDefaults
            saveRecipientMap()
        }
    }
    
    private func loadRecipientMap() {
        if let data = UserDefaults.standard.data(forKey: "conversationRecipientMap"),
           let decoded = try? JSONDecoder().decode([String: RecipientData].self, from: data) {
            // Load into backing storage without triggering setter
            let tempMap = decoded.reduce(into: [UUID: RecipientMeta]()) { result, pair in
                if let conversationId = UUID(uuidString: pair.key) {
                    result[conversationId] = RecipientMeta(
                        userId: pair.value.userId,
                        userName: pair.value.userName,
                        username: pair.value.username,
                        avatarUrl: pair.value.avatarUrl,
                        isOnline: pair.value.isOnline
                    )
                }
            }
            _conversationRecipientMap = tempMap
            for (id, data) in conversationRecipientMap {
            }
        } else {
        }
    }
    
    private func saveRecipientMap() {
        let encoded = _conversationRecipientMap.reduce(into: [String: RecipientData]()) { result, pair in
            let meta = pair.value
            result[pair.key.uuidString] = RecipientData(
                userId: meta.userId,
                userName: meta.userName,
                username: meta.username,
                avatarUrl: meta.avatarUrl,
                isOnline: meta.isOnline
            )
        }
        if let data = try? JSONEncoder().encode(encoded) {
            UserDefaults.standard.set(data, forKey: "conversationRecipientMap")
        } else {
        }
    }
    
    private struct RecipientData: Codable {
        let userId: UUID
        let userName: String
        let username: String?
        let avatarUrl: String?
        let isOnline: Bool
    }

    // MARK: - Initialization
    init() {
        loadUserData()
        loadRecipientMap() // Load persisted recipient mappings
        setupStories()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadUserData),
            name: .userDataUpdated,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadConversations),
            name: .conversationCreated,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadConversations),
            name: .messageSent,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConversationViewed),
            name: .conversationViewed,
            object: nil
        )
        
        Task {
            await loadConversations()
        }
    }

    // MARK: - Stories Setup
    private func setupStories() {
        if currentUser == nil {
            currentUser = Story(username: currentUserName, avatarUrl: avatarUrl)
        }

        // Stories можно оставить пустыми или загружать отдельно
        stories = []
    }
    
    // MARK: - Load Conversations
    @MainActor
    func loadConversations(forceReload: Bool = false) async {
        // Check cache validity
        if !forceReload && isDataLoaded, let lastLoad = lastLoadTime {
            let timeSinceLastLoad = Date().timeIntervalSince(lastLoad)
            if timeSinceLastLoad < cacheValidityDuration {
                // Cache is still valid, skip reload
                return
            }
        }
        
        isLoading = true
        defer { 
            isLoading = false
            lastLoadTime = Date()
            isDataLoaded = true
        }
        
        // Load current user ID
        if let userData = UserDefaults.standard.data(forKey: "userData"),
           let user = try? JSONDecoder().decode(User.self, from: userData) {
            currentUserId = user.id
        }
        
        guard currentUserId != nil else {
            errorMessage = "Не удалось загрузить данные пользователя"
            return
        }
        
        do {
            let response = try await conversationService.getConversations()
            
            
            if response.success, let conversations = response.data {
                
                
                // Filter out only deleted conversations - include all others
                // API may not return participants/lastMessage in list, but we'll handle that in convertToChat
                let validConversations = conversations.filter { conversation in
                    if conversation.isDeleted {
                        return false
                    }
                    
                    // Include all non-deleted conversations
                    // If participants are missing, we'll try to load them or use fallback values
                    return true
                }
                
                
                // If participants or lastMessage are missing, try to load messages to get user data
                var enrichedConversations = validConversations
                if validConversations.contains(where: { ($0.participants == nil || $0.participants?.isEmpty == true) || $0.lastMessage == nil }) {
                    var enriched: [Conversation] = []
                    for conversation in validConversations {
                        var enrichedConversation = conversation
                        
                        // If missing participants or lastMessage, try to get data from messages
                        if (conversation.participants == nil || conversation.participants?.isEmpty == true) || conversation.lastMessage == nil {
                            do {
                                let messagesResponse = try await conversationService.getMessages(conversationId: conversation.id, skip: 0, limit: 20)
                                if let messages = messagesResponse.data, !messages.isEmpty {
                                    
                                    // Get the most recent message as lastMessage
                                    let sortedMessages = messages.sorted { $0.createdAt > $1.createdAt }
                                    let lastMsg = sortedMessages.first
                                    
                                    if let lastMsg = lastMsg {
                                        enrichedConversation = Conversation(
                                            id: conversation.id,
                                            name: conversation.name,
                                            conversationType: conversation.conversationType,
                                            participants: conversation.participants,
                                            lastMessage: lastMsg,
                                            lastReadMessageId: conversation.lastReadMessageId,
                                            createdAt: conversation.createdAt,
                                            updatedAt: conversation.updatedAt,
                                            isDeleted: conversation.isDeleted,
                                            deletedAt: conversation.deletedAt,
                                            avatarUrl: conversation.avatarUrl
                                        )
                                    }
                                    
                                    // Try to extract participant data from messages if participants are missing
                                    if conversation.participants == nil || conversation.participants?.isEmpty == true {
                                        
                                        // Log all message senders
                                        for (index, message) in messages.enumerated() {
                                        }
                                        
                                        // Find a message from a user who is not the current user
                                        var foundParticipant: ConversationParticipant? = nil
                                        
                                        // First, try to find a message with a sender object
                                        if let otherUserMessage = messages.first(where: { 
                                            $0.senderId != currentUserId && $0.sender != nil 
                                        }),
                                           let sender = otherUserMessage.sender {
                                            foundParticipant = ConversationParticipant(
                                                id: UUID(),
                                                userId: sender.id,
                                                userName: sender.name,
                                                userAvatarUrl: sender.avatarUrl,
                                                isOnline: sender.isOnline,
                                                joinedAt: conversation.createdAt
                                            )
                                        } else {
                                            // If no sender object, try to find by senderId and get user data from API
                                            let otherUserIds = Set(messages.compactMap { msg in
                                                msg.senderId != currentUserId ? msg.senderId : nil
                                            })
                                            
                                            
                                            if let otherUserId = otherUserIds.first {
                                                // Try to get user data from messages - check if any message has sender with this ID
                                                for message in messages {
                                                    if message.senderId == otherUserId, let sender = message.sender {
                                                        foundParticipant = ConversationParticipant(
                                                            id: UUID(),
                                                            userId: sender.id,
                                                            userName: sender.name,
                                                            userAvatarUrl: sender.avatarUrl,
                                                            isOnline: sender.isOnline,
                                                            joinedAt: conversation.createdAt
                                                        )
                                                        break
                                                    }
                                                }
                                                
                                                // If still no participant, create one with minimal data
                                                if foundParticipant == nil {
                                                    // We'll need to fetch user data from API, but for now create minimal participant
                                                    // This will be handled in convertToChatData by using lastMessage.sender
                                                }
                                            }
                                        }
                                        
                                        if let participant = foundParticipant {
                                            let lastMsgToUse = enrichedConversation.lastMessage ?? lastMsg
                                            enrichedConversation = Conversation(
                                                id: conversation.id,
                                                name: conversation.name,
                                                conversationType: conversation.conversationType,
                                                participants: [participant],
                                                lastMessage: lastMsgToUse,
                                                lastReadMessageId: conversation.lastReadMessageId,
                                                createdAt: conversation.createdAt,
                                                updatedAt: conversation.updatedAt,
                                                isDeleted: conversation.isDeleted,
                                                deletedAt: conversation.deletedAt,
                                                avatarUrl: conversation.avatarUrl
                                            )
                                        } else {
                                        }
                                    }
                                }
                            } catch {
                            }
                        }
                        
                        enriched.append(enrichedConversation)
                    }
                    enrichedConversations = enriched
                }
                
                chats = enrichedConversations.map { conversation in
                    convertToChat(from: conversation)
                }
                // Sort by last message time (most recent first)
                chats.sort { $0.lastMessageTime > $1.lastMessageTime }
                
                
                // Also store ChatData for navigation
                chatDataList = convertToChatData(from: enrichedConversations)
                chatDataList.sort { $0.chat.lastMessageTime > $1.chat.lastMessageTime }
            } else {
                // If no conversations or error, show empty list
                chats = []
                chatDataList = []
                if let error = response.error {
                    errorMessage = error
                }
            }
        } catch {
            errorMessage = "Не удалось загрузить чаты: \(error.localizedDescription)"
            chats = []
            chatDataList = []
        }
    }
    
    // MARK: - Chat Data
    struct ChatData: Identifiable {
        let id: UUID
        let chat: Chat
        let recipientId: UUID?
        let recipientName: String
        let recipientUsername: String?
        let recipientAvatarUrl: String?
        let isRecipientOnline: Bool
        
        init(chat: Chat, recipientId: UUID?, recipientName: String, recipientUsername: String?, recipientAvatarUrl: String?, isRecipientOnline: Bool) {
            self.id = chat.id
            self.chat = chat
            self.recipientId = recipientId
            self.recipientName = recipientName
            self.recipientUsername = recipientUsername
            self.recipientAvatarUrl = recipientAvatarUrl
            self.isRecipientOnline = isRecipientOnline
        }
    }
    
    var chatDataList: [ChatData] = []
    
    // MARK: - Convert Conversation to Chat
    private func convertToChat(from conversation: Conversation) -> Chat {
        // Get other participant (not current user)
        let otherParticipant = conversation.participants?.first { participant in
            participant.userId != currentUserId
        }
        
        // Determine chat name
        let chatName: String
        if conversation.isGroup {
            chatName = conversation.name ?? "Группа"
        } else {
            // If no participant info, try to get name from lastMessage sender
            if let lastMessage = conversation.lastMessage,
               let senderName = lastMessage.sender?.name {
                chatName = senderName
            } else if let participantName = otherParticipant?.userName {
                chatName = participantName
            } else if let conversationName = conversation.name {
                chatName = conversationName
            } else {
                // Fallback: use conversation ID as name if nothing else available
                chatName = "Чат"
            }
        }
        
        // Get last message text (with deleted/edited/media-only handling)
        let lastMessageText: String
        if let lastMessage = conversation.lastMessage {
            if lastMessage.isDeleted {
                // Deleted message
                lastMessageText = "Сообщение удалено"
            } else {
                // Check if message has only media (no text or only whitespace)
                let trimmedContent = lastMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
                let hasText = !trimmedContent.isEmpty
                let hasMedia = !lastMessage.media.isEmpty
                
                if !hasText && hasMedia {
                    // Message contains only media, show "Фото"
                    lastMessageText = "Фото"
                } else if lastMessage.isEdited {
                    // Edited text message
                    lastMessageText = trimmedContent.isEmpty ? "Сообщение изменено" : "\(trimmedContent) (изменено)"
                } else {
                    lastMessageText = trimmedContent.isEmpty ? "Пустое сообщение" : trimmedContent
                }
            }
        } else {
            lastMessageText = "Нет сообщений"
        }
        
        // Get last message time - use updatedAt if no lastMessage
        let lastMessageTime: Date
        if let lastMessage = conversation.lastMessage {
            lastMessageTime = lastMessage.createdAt
        } else {
            lastMessageTime = conversation.updatedAt
        }
        
        // Get avatar URL
        let avatarUrl: String?
        if conversation.isGroup {
            avatarUrl = conversation.avatarUrl
        } else {
            avatarUrl = otherParticipant?.userAvatarUrl ?? conversation.avatarUrl
        }
        
        // Determine if there are unread messages
        // If lastMessage exists and lastReadMessageId is different (or nil), there are unread messages
        let hasUnreadMessages: Bool
        if let lastMessage = conversation.lastMessage {
            // Check if last message is from current user (we don't show unread for our own messages)
            if lastMessage.senderId == currentUserId {
                hasUnreadMessages = false
            } else {
                // Message is from other user - check if it's been read
                hasUnreadMessages = conversation.lastReadMessageId != lastMessage.id
            }
        } else {
            hasUnreadMessages = false
        }
        
        return Chat(
            id: conversation.id,
            username: chatName,
            lastMessage: lastMessageText,
            lastMessageTime: lastMessageTime,
            avatarUrl: avatarUrl,
            isGroup: conversation.isGroup,
            hasUnreadMessages: hasUnreadMessages
        )
    }
    
    // MARK: - Convert Conversations to ChatData
    private func convertToChatData(from conversations: [Conversation]) -> [ChatData] {
        
        return conversations.map { conversation in
            
            let otherParticipant = conversation.participants?.first { participant in
                participant.userId != currentUserId
            }
            
            
            let chatName: String
            let recipientUsername: String?
            let recipientAvatarUrl: String?
            
            if conversation.isGroup {
                chatName = conversation.name ?? "Группа"
                recipientUsername = nil
                recipientAvatarUrl = conversation.avatarUrl
            } else {
                // Priority 1: lastMessage.sender has most complete data (including username)
                if let lastMessage = conversation.lastMessage,
                   let sender = lastMessage.sender,
                   sender.id != currentUserId {
                    // Use sender data if it's not the current user
                    chatName = sender.name
                    recipientUsername = sender.username
                    recipientAvatarUrl = sender.avatarUrl
                } else if let participant = otherParticipant {
                    // Priority 2: Fallback to participant data (no username available)
                    chatName = participant.userName
                    recipientUsername = nil // ConversationParticipant doesn't have username
                    recipientAvatarUrl = participant.userAvatarUrl
                } else if let lastMessage = conversation.lastMessage,
                          lastMessage.senderId != currentUserId {
                    // Priority 3: Use lastMessage senderName even if sender object is missing
                    chatName = lastMessage.senderName
                    recipientUsername = nil
                    recipientAvatarUrl = nil
                } else if let lastMessage = conversation.lastMessage,
                          lastMessage.senderId == currentUserId {
                    // All messages from current user - check if we have recipient data stored
                    if let recipientData = conversationRecipientMap[conversation.id] {
                        chatName = recipientData.userName
                        recipientUsername = recipientData.username
                        recipientAvatarUrl = recipientData.avatarUrl
                    } else {
                        // No stored data - try to get from conversation name or use fallback
                        // For now, use fallback - data will be loaded when chat is opened
                        chatName = conversation.name?.isEmpty == false ? conversation.name! : "Новый чат"
                        recipientUsername = nil
                        recipientAvatarUrl = nil
                    }
                } else {
                    // Last resort: use conversation name or fallback
                    chatName = conversation.name ?? "Чат"
                    recipientUsername = nil
                    recipientAvatarUrl = conversation.avatarUrl
                }
            }
            
            // Determine recipientId and isRecipientOnline
            let recipientId: UUID?
            let isRecipientOnline: Bool
            
            // Priority 1: Use sender ID from lastMessage if available
            if let lastMessage = conversation.lastMessage,
               let sender = lastMessage.sender,
               sender.id != currentUserId {
                recipientId = sender.id
                isRecipientOnline = sender.isOnline
            } else if let participant = otherParticipant {
                // Priority 2: Use participant ID
                recipientId = participant.userId
                isRecipientOnline = participant.isOnline
            } else if let lastMessage = conversation.lastMessage,
                      lastMessage.senderId != currentUserId {
                // Priority 3: Use senderId even if sender object is missing
                recipientId = lastMessage.senderId
                isRecipientOnline = false
            } else if let recipientData = conversationRecipientMap[conversation.id] {
                // Priority 4: Use stored recipient data (for conversations where all messages are from current user)
                recipientId = recipientData.userId
                isRecipientOnline = recipientData.isOnline
            } else {
                recipientId = nil
                isRecipientOnline = false
            }
            
            let chatData = ChatData(
                chat: convertToChat(from: conversation),
                recipientId: recipientId,
                recipientName: chatName,
                recipientUsername: recipientUsername,
                recipientAvatarUrl: recipientAvatarUrl,
                isRecipientOnline: isRecipientOnline
            )
            
            
            return chatData
        }
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
        }
    }

    @objc
    private func reloadUserData() {
        loadUserData()
    }
    
    @objc
    private func reloadConversations() {
        Task {
            // Force reload when conversation is created or message is sent
            await loadConversations(forceReload: true)
        }
    }
    
    @objc
    private func handleConversationViewed(_ notification: Notification) {
        // When a conversation is viewed, mark it as read locally without forcing full reload
        guard let conversationId = notification.object as? UUID else { return }
        
        // Update unread flag in chats list
        if let index = chats.firstIndex(where: { $0.id == conversationId }) {
            let chat = chats[index]
            chats[index] = Chat(
                id: chat.id,
                username: chat.username,
                lastMessage: chat.lastMessage,
                lastMessageTime: chat.lastMessageTime,
                avatarUrl: chat.avatarUrl,
                isGroup: chat.isGroup,
                hasUnreadMessages: false
            )
        }
        
        // Also update corresponding ChatData entry if needed
        if let dataIndex = chatDataList.firstIndex(where: { $0.chat.id == conversationId }) {
            let existing = chatDataList[dataIndex]
            let updatedChat = Chat(
                id: existing.chat.id,
                username: existing.chat.username,
                lastMessage: existing.chat.lastMessage,
                lastMessageTime: existing.chat.lastMessageTime,
                avatarUrl: existing.chat.avatarUrl,
                isGroup: existing.chat.isGroup,
                hasUnreadMessages: false
            )
            
            chatDataList[dataIndex] = ChatData(
                chat: updatedChat,
                recipientId: existing.recipientId,
                recipientName: existing.recipientName,
                recipientUsername: existing.recipientUsername,
                recipientAvatarUrl: existing.recipientAvatarUrl,
                isRecipientOnline: existing.isRecipientOnline
            )
        }
    }

    // MARK: - Chat Management
    func openChat(with userId: UUID, userName: String, isOnline: Bool) {
        Task {
            await openChatAsync(with: userId, userName: userName, isOnline: isOnline)
        }
    }
    
    @MainActor
    private func openChatAsync(with userId: UUID, userName: String, isOnline: Bool) async {
        
        // Use findOrCreateConversation to avoid creating duplicate chats
        do {
            let response = try await conversationService.findOrCreateConversation(with: userId)
            
            if response.success, let conversation = response.data {
                // Found or created conversation - open it
                
                // Check if this is a new conversation or existing one
                if let participants = conversation.participants,
                   participants.contains(where: { $0.userId == userId }) {
                } else {
                }
                
                // Try to get full user data (username, avatarUrl) from API
                var username: String? = nil
                var avatarUrl: String? = nil
                var isOnlineStatus = isOnline
                
                do {
                    let userResponse = try await profileService.getUserById(userId)
                    if userResponse.success, let user = userResponse.data {
                        username = user.username
                        avatarUrl = user.avatarUrl
                        isOnlineStatus = user.isOnline
                    } else {
                    }
                } catch {
                    // Continue with provided data
                }
                
                // Store recipient data for this conversation
                conversationRecipientMap[conversation.id] = RecipientMeta(
                    userId: userId,
                    userName: userName,
                    username: username,
                    avatarUrl: avatarUrl,
                    isOnline: isOnlineStatus
                )
                
                selectedChatInfo = ChatInfo(
                    userId: userId,
                    userName: userName,
                    isOnline: isOnlineStatus,
                    conversationId: conversation.id
                )
                isUserProfileActive = false
                
                // Reload conversations to update the list with new recipient data
                await loadConversations()
            } else {
                // If creation failed, still try to open chat (ChatViewModel will handle it)
                selectedChatInfo = ChatInfo(
                    userId: userId,
                    userName: userName,
                    isOnline: isOnline,
                    conversationId: nil
                )
                isUserProfileActive = false
            }
        } catch {
            // On error, still try to open chat
            selectedChatInfo = ChatInfo(
                userId: userId,
                userName: userName,
                isOnline: isOnline,
                conversationId: nil
            )
            isUserProfileActive = false
        }
    }

    // MARK: - Delete All Conversations (Temporary - for cleanup)
    @MainActor
    func deleteAllConversations() async {
        do {
            let response = try await conversationService.getConversations()
            if let conversations = response.data {
                for conversation in conversations {
                    do {
                        _ = try await conversationService.deleteConversation(id: conversation.id)
                    } catch {
                    }
                }
                // Reload conversations after deletion
                await loadConversations()
            }
        } catch {
        }
    }

    // MARK: - Logout
    func logout() {
        // Clear all user data
        UserDefaults.standard.removeObject(forKey: "accessToken")
        UserDefaults.standard.removeObject(forKey: "refreshToken")
        UserDefaults.standard.removeObject(forKey: "accessTokenExpiration")
        UserDefaults.standard.removeObject(forKey: "refreshTokenExpiration")
        UserDefaults.standard.removeObject(forKey: "userData")
        UserDefaults.standard.synchronize()
        
        // Clear avatar cache
        ImageCacheService.shared.clearCache()
        
        // Reset user data
        currentUserName = "Имя пользователя"
        username = "username"
        avatarUrl = nil
        currentUser = nil
    }
}
