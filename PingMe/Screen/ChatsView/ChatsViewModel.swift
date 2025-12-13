import Foundation
import Observation

extension Notification.Name {
    static let userDataUpdated = Notification.Name("userDataUpdated")
    static let conversationCreated = Notification.Name("conversationCreated")
    static let messageSent = Notification.Name("messageSent")
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
    // Store mapping of conversationId -> recipient data for conversations where all messages are from current user
    private var _conversationRecipientMap: [UUID: (userId: UUID, userName: String, username: String?, avatarUrl: String?, isOnline: Bool)] = [:]
    
    private var conversationRecipientMap: [UUID: (userId: UUID, userName: String, username: String?, avatarUrl: String?, isOnline: Bool)] {
        get { _conversationRecipientMap }
        set {
            _conversationRecipientMap = newValue
            // Persist to UserDefaults
            saveRecipientMap()
        }
    }
    
    private func loadRecipientMap() {
        print("🔵 ChatsViewModel: loadRecipientMap called")
        if let data = UserDefaults.standard.data(forKey: "conversationRecipientMap"),
           let decoded = try? JSONDecoder().decode([String: RecipientData].self, from: data) {
            // Load into backing storage without triggering setter
            let tempMap = decoded.reduce(into: [UUID: (userId: UUID, userName: String, username: String?, avatarUrl: String?, isOnline: Bool)]()) { result, pair in
                if let conversationId = UUID(uuidString: pair.key) {
                    result[conversationId] = (
                        userId: pair.value.userId,
                        userName: pair.value.userName,
                        username: pair.value.username,
                        avatarUrl: pair.value.avatarUrl,
                        isOnline: pair.value.isOnline
                    )
                }
            }
            _conversationRecipientMap = tempMap
            print("🔵 ChatsViewModel: ✅ Loaded \(conversationRecipientMap.count) recipient mappings from UserDefaults")
            for (id, data) in conversationRecipientMap {
                print("🔵 ChatsViewModel:   - conversation \(id): userId=\(data.userId), userName=\(data.userName)")
            }
        } else {
            print("🔵 ChatsViewModel: No recipient mappings found in UserDefaults")
        }
    }
    
    private func saveRecipientMap() {
        let encoded = _conversationRecipientMap.reduce(into: [String: RecipientData]()) { result, pair in
            result[pair.key.uuidString] = RecipientData(
                userId: pair.value.userId,
                userName: pair.value.userName,
                username: pair.value.username,
                avatarUrl: pair.value.avatarUrl,
                isOnline: pair.value.isOnline
            )
        }
        if let data = try? JSONEncoder().encode(encoded) {
            UserDefaults.standard.set(data, forKey: "conversationRecipientMap")
            print("🔵 ChatsViewModel: ✅ Saved \(_conversationRecipientMap.count) recipient mappings to UserDefaults")
        } else {
            print("🔵 ChatsViewModel: ⚠️ Failed to encode recipient mappings")
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
    func loadConversations() async {
        isLoading = true
        defer { isLoading = false }
        
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
            
            print("🔵 ChatsViewModel: loadConversations - response.success: \(response.success)")
            
            if response.success, let conversations = response.data {
                print("🔵 ChatsViewModel: Loaded \(conversations.count) conversations from API")
                
                // Log details for each conversation
                for conversation in conversations {
                    print("🔵 ChatsViewModel: Conversation \(conversation.id):")
                    print("   - isDeleted: \(conversation.isDeleted)")
                    print("   - isGroup: \(conversation.isGroup)")
                    print("   - name: \(conversation.name ?? "nil")")
                    print("   - participants count: \(conversation.participants?.count ?? 0)")
                    print("   - has lastMessage: \(conversation.lastMessage != nil)")
                    if let lastMessage = conversation.lastMessage {
                        print("   - lastMessage content: \(lastMessage.content)")
                        print("   - lastMessage sender: \(lastMessage.sender?.name ?? "nil")")
                        print("   - lastMessage sender username: \(lastMessage.sender?.username ?? "nil")")
                        print("   - lastMessage sender avatarUrl: \(lastMessage.sender?.avatarUrl ?? "nil")")
                    }
                    if let participants = conversation.participants {
                        for participant in participants {
                            print("   - participant: \(participant.userName) (id: \(participant.userId), avatar: \(participant.userAvatarUrl ?? "nil"))")
                        }
                    }
                }
                
                // Filter out only deleted conversations - include all others
                // API may not return participants/lastMessage in list, but we'll handle that in convertToChat
                let validConversations = conversations.filter { conversation in
                    if conversation.isDeleted {
                        print("🔵 ChatsViewModel: Excluding conversation \(conversation.id) - is deleted")
                        return false
                    }
                    
                    // Include all non-deleted conversations
                    // If participants are missing, we'll try to load them or use fallback values
                    print("🔵 ChatsViewModel: Including conversation \(conversation.id) - not deleted")
                    return true
                }
                
                print("🔵 ChatsViewModel: After filtering: \(validConversations.count) valid conversations")
                
                // If participants or lastMessage are missing, try to load messages to get user data
                var enrichedConversations = validConversations
                if validConversations.contains(where: { ($0.participants == nil || $0.participants?.isEmpty == true) || $0.lastMessage == nil }) {
                    print("🔵 ChatsViewModel: Some conversations missing participants or lastMessage, loading messages...")
                    var enriched: [Conversation] = []
                    for conversation in validConversations {
                        var enrichedConversation = conversation
                        
                        // If missing participants or lastMessage, try to get data from messages
                        if (conversation.participants == nil || conversation.participants?.isEmpty == true) || conversation.lastMessage == nil {
                            print("🔵 ChatsViewModel: Loading messages for conversation \(conversation.id) to get user data...")
                            do {
                                let messagesResponse = try await conversationService.getMessages(conversationId: conversation.id, skip: 0, limit: 20)
                                if let messages = messagesResponse.data, !messages.isEmpty {
                                    print("🔵 ChatsViewModel: Loaded \(messages.count) messages for conversation \(conversation.id)")
                                    
                                    // Get the most recent message as lastMessage
                                    let sortedMessages = messages.sorted { $0.createdAt > $1.createdAt }
                                    let lastMsg = sortedMessages.first
                                    
                                    if let lastMsg = lastMsg {
                                        print("🔵 ChatsViewModel: Using message \(lastMsg.id) as lastMessage: \(lastMsg.content)")
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
                                        print("🔵 ChatsViewModel: Extracting participant data from messages...")
                                        print("🔵 ChatsViewModel: Checking \(messages.count) messages for other user...")
                                        
                                        // Log all message senders
                                        for (index, message) in messages.enumerated() {
                                            print("🔵 ChatsViewModel: Message \(index): senderId=\(message.senderId), sender=\(message.sender?.name ?? "nil"), isCurrentUser=\(message.senderId == currentUserId)")
                                        }
                                        
                                        // Find a message from a user who is not the current user
                                        var foundParticipant: ConversationParticipant? = nil
                                        
                                        // First, try to find a message with a sender object
                                        if let otherUserMessage = messages.first(where: { 
                                            $0.senderId != currentUserId && $0.sender != nil 
                                        }),
                                           let sender = otherUserMessage.sender {
                                            print("🔵 ChatsViewModel: ✅ Found other user in messages with sender object: \(sender.name) (id: \(sender.id), username: \(sender.username ?? "nil"), avatarUrl: \(sender.avatarUrl ?? "nil"))")
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
                                            
                                            print("🔵 ChatsViewModel: Found \(otherUserIds.count) unique other user IDs: \(otherUserIds.map { $0.uuidString })")
                                            
                                            if let otherUserId = otherUserIds.first {
                                                print("🔵 ChatsViewModel: Trying to get user data for ID: \(otherUserId)")
                                                // Try to get user data from messages - check if any message has sender with this ID
                                                for message in messages {
                                                    if message.senderId == otherUserId, let sender = message.sender {
                                                        print("🔵 ChatsViewModel: ✅ Found sender data in message: \(sender.name)")
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
                                                    print("🔵 ChatsViewModel: ⚠️ No sender data in messages, creating minimal participant for ID: \(otherUserId)")
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
                                            print("🔵 ChatsViewModel: ✅ Enriched conversation with participant: \(participant.userName) and lastMessage: \(lastMsgToUse?.content ?? "nil")")
                                        } else {
                                            print("🔵 ChatsViewModel: ⚠️ Could not create participant from messages")
                                            print("🔵 ChatsViewModel: All messages are from current user - this is a new chat")
                                            print("🔵 ChatsViewModel: Will need to get recipient data when opening chat")
                                        }
                                    }
                                }
                            } catch {
                                print("🔵 ChatsViewModel: Failed to load messages for \(conversation.id): \(error)")
                            }
                        }
                        
                        enriched.append(enrichedConversation)
                    }
                    enrichedConversations = enriched
                }
                
                chats = enrichedConversations.map { conversation in
                    let chat = convertToChat(from: conversation)
                    print("🔵 ChatsViewModel: Created Chat for conversation \(conversation.id):")
                    print("   - username: \(chat.username)")
                    print("   - lastMessage: \(chat.lastMessage)")
                    print("   - avatarUrl: \(chat.avatarUrl ?? "nil")")
                    return chat
                }
                // Sort by last message time (most recent first)
                chats.sort { $0.lastMessageTime > $1.lastMessageTime }
                
                print("🔵 ChatsViewModel: Created \(chats.count) chats")
                
                // Also store ChatData for navigation
                chatDataList = convertToChatData(from: enrichedConversations)
                chatDataList.sort { $0.chat.lastMessageTime > $1.chat.lastMessageTime }
                
                print("🔵 ChatsViewModel: Created \(chatDataList.count) chatData items")
                for chatData in chatDataList {
                    print("🔵 ChatsViewModel: ChatData \(chatData.id):")
                    print("   - recipientName: \(chatData.recipientName)")
                    print("   - recipientUsername: \(chatData.recipientUsername ?? "nil")")
                    print("   - recipientAvatarUrl: \(chatData.recipientAvatarUrl ?? "nil")")
                    print("   - recipientId: \(chatData.recipientId?.uuidString ?? "nil")")
                    print("   - isRecipientOnline: \(chatData.isRecipientOnline)")
                    print("   - chat.lastMessage: \(chatData.chat.lastMessage)")
                }
            } else {
                // If no conversations or error, show empty list
                print("🔵 ChatsViewModel: No conversations or error - response.success: \(response.success), error: \(response.error ?? "none")")
                chats = []
                chatDataList = []
                if let error = response.error {
                    errorMessage = error
                }
            }
        } catch {
            print("🔵 ChatsViewModel: Error loading conversations: \(error)")
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
        
        // Get last message text
        let lastMessageText: String
        if let lastMessage = conversation.lastMessage {
            if lastMessage.isDeleted {
                lastMessageText = "Сообщение удалено"
            } else {
                lastMessageText = lastMessage.content
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
        
        return Chat(
            id: conversation.id,
            username: chatName,
            lastMessage: lastMessageText,
            lastMessageTime: lastMessageTime,
            avatarUrl: avatarUrl,
            isGroup: conversation.isGroup
        )
    }
    
    // MARK: - Convert Conversations to ChatData
    private func convertToChatData(from conversations: [Conversation]) -> [ChatData] {
        print("🔵 ChatsViewModel: convertToChatData called for \(conversations.count) conversations")
        print("🔵 ChatsViewModel: currentUserId: \(currentUserId?.uuidString ?? "nil")")
        
        return conversations.map { conversation in
            print("🔵 ChatsViewModel: Processing conversation \(conversation.id)")
            
            let otherParticipant = conversation.participants?.first { participant in
                participant.userId != currentUserId
            }
            
            print("🔵 ChatsViewModel: otherParticipant: \(otherParticipant?.userName ?? "nil") (id: \(otherParticipant?.userId.uuidString ?? "nil"))")
            print("🔵 ChatsViewModel: conversation.lastMessage: \(conversation.lastMessage?.content ?? "nil")")
            print("🔵 ChatsViewModel: conversation.lastMessage.sender: \(conversation.lastMessage?.sender?.name ?? "nil")")
            print("🔵 ChatsViewModel: conversation.lastMessage.senderId: \(conversation.lastMessage?.senderId.uuidString ?? "nil")")
            
            let chatName: String
            let recipientUsername: String?
            let recipientAvatarUrl: String?
            
            if conversation.isGroup {
                chatName = conversation.name ?? "Группа"
                recipientUsername = nil
                recipientAvatarUrl = conversation.avatarUrl
                print("🔵 ChatsViewModel: Group chat - name: \(chatName), avatarUrl: \(recipientAvatarUrl ?? "nil")")
            } else {
                // Priority 1: lastMessage.sender has most complete data (including username)
                if let lastMessage = conversation.lastMessage,
                   let sender = lastMessage.sender,
                   sender.id != currentUserId {
                    // Use sender data if it's not the current user
                    chatName = sender.name
                    recipientUsername = sender.username
                    recipientAvatarUrl = sender.avatarUrl
                    print("🔵 ChatsViewModel: ✅ Using lastMessage.sender data:")
                    print("   - name: \(chatName)")
                    print("   - username: \(recipientUsername ?? "nil")")
                    print("   - avatarUrl: \(recipientAvatarUrl ?? "nil")")
                } else if let participant = otherParticipant {
                    // Priority 2: Fallback to participant data (no username available)
                    chatName = participant.userName
                    recipientUsername = nil // ConversationParticipant doesn't have username
                    recipientAvatarUrl = participant.userAvatarUrl
                    print("🔵 ChatsViewModel: ✅ Using participant data:")
                    print("   - name: \(chatName)")
                    print("   - username: nil (not available in participant)")
                    print("   - avatarUrl: \(recipientAvatarUrl ?? "nil")")
                } else if let lastMessage = conversation.lastMessage,
                          lastMessage.senderId != currentUserId {
                    // Priority 3: Use lastMessage senderName even if sender object is missing
                    chatName = lastMessage.senderName
                    recipientUsername = nil
                    recipientAvatarUrl = nil
                    print("🔵 ChatsViewModel: ⚠️ Using lastMessage.senderName (no sender object):")
                    print("   - name: \(chatName)")
                    print("   - senderId: \(lastMessage.senderId.uuidString)")
                } else if let lastMessage = conversation.lastMessage,
                          lastMessage.senderId == currentUserId {
                    // All messages from current user - check if we have recipient data stored
                    print("🔵 ChatsViewModel: Checking conversationRecipientMap for conversation \(conversation.id)")
                    print("🔵 ChatsViewModel: conversationRecipientMap keys: \(conversationRecipientMap.keys.map { $0.uuidString })")
                    if let recipientData = conversationRecipientMap[conversation.id] {
                        chatName = recipientData.userName
                        recipientUsername = recipientData.username
                        recipientAvatarUrl = recipientData.avatarUrl
                        print("🔵 ChatsViewModel: ✅ Using stored recipient data for conversation \(conversation.id):")
                        print("   - name: \(chatName)")
                        print("   - username: \(recipientUsername ?? "nil")")
                        print("   - avatarUrl: \(recipientAvatarUrl ?? "nil")")
                    } else {
                        // No stored data - try to get from conversation name or use fallback
                        // For now, use fallback - data will be loaded when chat is opened
                        chatName = conversation.name?.isEmpty == false ? conversation.name! : "Новый чат"
                        recipientUsername = nil
                        recipientAvatarUrl = nil
                        print("🔵 ChatsViewModel: ⚠️ All messages from current user - no stored recipient data:")
                        print("   - name: \(chatName)")
                        print("   - conversationRecipientMap.count: \(conversationRecipientMap.count)")
                        print("   - Will load data when chat is opened")
                    }
                } else {
                    // Last resort: use conversation name or fallback
                    chatName = conversation.name ?? "Чат"
                    recipientUsername = nil
                    recipientAvatarUrl = conversation.avatarUrl
                    print("🔵 ChatsViewModel: ⚠️ Using fallback data:")
                    print("   - name: \(chatName)")
                    print("   - username: nil")
                    print("   - avatarUrl: \(recipientAvatarUrl ?? "nil")")
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
                print("🔵 ChatsViewModel: recipientId from lastMessage.sender: \(recipientId?.uuidString ?? "nil")")
            } else if let participant = otherParticipant {
                // Priority 2: Use participant ID
                recipientId = participant.userId
                isRecipientOnline = participant.isOnline
                print("🔵 ChatsViewModel: recipientId from participant: \(recipientId?.uuidString ?? "nil")")
            } else if let lastMessage = conversation.lastMessage,
                      lastMessage.senderId != currentUserId {
                // Priority 3: Use senderId even if sender object is missing
                recipientId = lastMessage.senderId
                isRecipientOnline = false
                print("🔵 ChatsViewModel: recipientId from lastMessage.senderId: \(recipientId?.uuidString ?? "nil")")
            } else if let recipientData = conversationRecipientMap[conversation.id] {
                // Priority 4: Use stored recipient data (for conversations where all messages are from current user)
                recipientId = recipientData.userId
                isRecipientOnline = recipientData.isOnline
                print("🔵 ChatsViewModel: recipientId from stored recipient data: \(recipientId?.uuidString ?? "nil")")
            } else {
                recipientId = nil
                isRecipientOnline = false
                print("🔵 ChatsViewModel: recipientId: nil (no data available)")
            }
            
            let chatData = ChatData(
                chat: convertToChat(from: conversation),
                recipientId: recipientId,
                recipientName: chatName,
                recipientUsername: recipientUsername,
                recipientAvatarUrl: recipientAvatarUrl,
                isRecipientOnline: isRecipientOnline
            )
            
            print("🔵 ChatsViewModel: Created ChatData for conversation \(conversation.id):")
            print("   - recipientName: \(chatData.recipientName)")
            print("   - recipientUsername: \(chatData.recipientUsername ?? "nil")")
            print("   - recipientAvatarUrl: \(chatData.recipientAvatarUrl ?? "nil")")
            print("   - recipientId: \(chatData.recipientId?.uuidString ?? "nil")")
            
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
            print("Failed to decode user data: \(error)")
        }
    }

    @objc
    private func reloadUserData() {
        loadUserData()
    }
    
    @objc
    private func reloadConversations() {
        Task {
            await loadConversations()
        }
    }

    // MARK: - Chat Management
    func openChat(with userId: UUID, userName: String, isOnline: Bool) {
        print("🔵 ChatsViewModel: openChat called for userId: \(userId), userName: \(userName)")
        Task {
            await openChatAsync(with: userId, userName: userName, isOnline: isOnline)
        }
    }
    
    @MainActor
    private func openChatAsync(with userId: UUID, userName: String, isOnline: Bool) async {
        print("🔵 ChatsViewModel: openChatAsync called for userId: \(userId), userName: \(userName)")
        
        // Use findOrCreateConversation to avoid creating duplicate chats
        do {
            let response = try await conversationService.findOrCreateConversation(with: userId)
            
            if response.success, let conversation = response.data {
                // Found or created conversation - open it
                print("🔵 ChatsViewModel: ✅ Found/created conversation \(conversation.id) for user \(userId)")
                
                // Check if this is a new conversation or existing one
                if let participants = conversation.participants,
                   participants.contains(where: { $0.userId == userId }) {
                    print("🔵 ChatsViewModel: This is an EXISTING conversation with messages")
                } else {
                    print("🔵 ChatsViewModel: This is a NEW conversation (no participants info)")
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
                        print("🔵 ChatsViewModel: ✅ Loaded user data for \(userId): name=\(user.name), username=\(user.username ?? "nil"), avatarUrl=\(user.avatarUrl ?? "nil")")
                    } else {
                        print("🔵 ChatsViewModel: ⚠️ getUserById returned success=\(userResponse.success), but data is nil")
                    }
                } catch {
                    print("🔵 ChatsViewModel: ⚠️ Failed to load user data for \(userId): \(error)")
                    // Continue with provided data
                }
                
                // Store recipient data for this conversation
                conversationRecipientMap[conversation.id] = (userId: userId, userName: userName, username: username, avatarUrl: avatarUrl, isOnline: isOnlineStatus)
                print("🔵 ChatsViewModel: Stored recipient data for conversation \(conversation.id): userId=\(userId), userName=\(userName), username=\(username ?? "nil"), avatarUrl=\(avatarUrl ?? "nil")")
                
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
                print("🔵 ChatsViewModel: ⚠️ Failed to find/create conversation, opening chat anyway")
                selectedChatInfo = ChatInfo(
                    userId: userId,
                    userName: userName,
                    isOnline: isOnline,
                    conversationId: nil
                )
                isUserProfileActive = false
            }
        } catch {
            print("🔵 ChatsViewModel: ❌ Error in findOrCreateConversation: \(error)")
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
        print("🔵 ChatsViewModel: Starting to delete all conversations...")
        do {
            let response = try await conversationService.getConversations()
            if let conversations = response.data {
                print("🔵 ChatsViewModel: Found \(conversations.count) conversations to delete")
                for conversation in conversations {
                    do {
                        _ = try await conversationService.deleteConversation(id: conversation.id)
                        print("🔵 ChatsViewModel: Deleted conversation \(conversation.id)")
                    } catch {
                        print("🔵 ChatsViewModel: Failed to delete conversation \(conversation.id): \(error)")
                    }
                }
                // Reload conversations after deletion
                await loadConversations()
                print("🔵 ChatsViewModel: Finished deleting conversations")
            }
        } catch {
            print("🔵 ChatsViewModel: Error loading conversations for deletion: \(error)")
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
