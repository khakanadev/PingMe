import Foundation
import Combine

// MARK: - View Model
@MainActor
final class ChatViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var messages: [MessageDisplay] = []
    @Published var recipientName: String
    @Published var recipientUsername: String?
    @Published var recipientAvatarUrl: String?
    @Published var recipientId: UUID
    @Published var isRecipientOnline: Bool
    @Published var newMessageText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var conversationId: UUID?
    @Published var isTyping: Bool = false
    @Published var typingUserName: String = ""
    
    // MARK: - Private Properties
    private let conversationService = ConversationService()
    private let webSocketService = WebSocketService.shared
    private var currentUserId: UUID?
    private var isInitializing = false // Prevent multiple initializations

    // MARK: - Initialization
    init(recipientId: UUID, recipientName: String, recipientUsername: String? = nil, recipientAvatarUrl: String? = nil, isRecipientOnline: Bool = true, conversationId: UUID? = nil) {
        print("🔵 ChatViewModel: init called for recipientId: \(recipientId), conversationId: \(conversationId?.uuidString ?? "nil")")
        self.recipientId = recipientId
        self.recipientName = recipientName
        self.recipientUsername = recipientUsername
        self.recipientAvatarUrl = recipientAvatarUrl
        self.isRecipientOnline = isRecipientOnline
        self.conversationId = conversationId
        
        Task { @MainActor in
            await initialize()
        }
    }
    
    // MARK: - Initialization
    @MainActor
    private func initialize() async {
        // Prevent multiple initializations
        guard !isInitializing else {
            print("🔵 ChatViewModel: initialize() skipped - already initializing")
            return
        }
        isInitializing = true
        defer { 
            isInitializing = false
            print("🔵 ChatViewModel: initialize() completed")
        }
        
        print("🔵 ChatViewModel: initialize() started for recipientId: \(recipientId)")
        isLoading = true
        
        // Load current user ID
        if let userData = UserDefaults.standard.data(forKey: "userData"),
           let user = try? JSONDecoder().decode(User.self, from: userData) {
            currentUserId = user.id
        }
        
        guard currentUserId != nil else {
            errorMessage = "Не удалось загрузить данные пользователя"
            isLoading = false
            return
        }
        
        // Always call connect: WebSocketService will either connect or re-authenticate with current token
        await webSocketService.connect()
        
        // Wait for authentication
        var attempts = 0
        while !webSocketService.isAuthenticated && attempts < 10 {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            attempts += 1
        }
        
        guard webSocketService.isAuthenticated else {
            errorMessage = "Не удалось аутентифицировать WebSocket соединение"
            isLoading = false
            return
        }
        
        // Get or create conversation
        if let existingConversationId = conversationId {
            self.conversationId = existingConversationId
            await loadMessages()
            await subscribeToConversation()
        } else {
            await findOrCreateConversation()
        }
        
        // Setup WebSocket handlers (must be on MainActor)
        setupWebSocketHandlers()
        
        // Ensure isLoading is set to false after everything is done
        isLoading = false
        print("🔵 ChatViewModel: isLoading set to false (final)")
    }
    
    // MARK: - Conversation Management
    
    private func findOrCreateConversation() async {
        print("🔵 ChatViewModel: findOrCreateConversation called for recipientId: \(recipientId)")
        
        // Prevent multiple simultaneous calls
        guard conversationId == nil else {
            print("🔵 ChatViewModel: findOrCreateConversation skipped - conversationId already exists: \(conversationId!)")
            return
        }
        
        do {
            // First, try to find existing conversation
            print("🔵 ChatViewModel: Searching for existing conversation...")
            let conversationsResponse = try await conversationService.getConversations()
            
            if let conversations = conversationsResponse.data,
               let existingConversation = conversations.first(where: { conversation in
                   !conversation.isGroup && conversation.participants?.contains { $0.userId == recipientId } == true
               }) {
                print("🔵 ChatViewModel: Found existing conversation: \(existingConversation.id)")
                await MainActor.run {
                    conversationId = existingConversation.id
                }
                await loadMessages()
                await subscribeToConversation()
                await MainActor.run {
                    setupWebSocketHandlers()
                }
                return
            }
            
            // If not found, create new conversation
            print("🔵 ChatViewModel: No existing conversation found, creating new one...")
            let response = try await conversationService.createConversation(participantIds: [recipientId])
            
            if response.success, let conversation = response.data {
                print("🔵 ChatViewModel: Created new conversation: \(conversation.id)")
                await MainActor.run {
                    conversationId = conversation.id
                }
                // Notify that conversation was created
                NotificationCenter.default.post(name: .conversationCreated, object: nil)
                await loadMessages()
                await subscribeToConversation()
                await MainActor.run {
                    setupWebSocketHandlers()
                }
            } else {
                print("🔵 ChatViewModel: Failed to create conversation: \(response.error ?? "Unknown error")")
                // Allow user to send message anyway - conversation will be created via WebSocket
                await MainActor.run {
                    errorMessage = nil
                    isLoading = false
                }
            }
        } catch {
            print("🔵 ChatViewModel: Error in findOrCreateConversation: \(error)")
            // On error, still allow sending message
            await MainActor.run {
                errorMessage = nil
                isLoading = false
            }
        }
    }
    
    private func loadMessages() async {
        guard let conversationId = conversationId else {
            print("🔵 ChatViewModel: loadMessages - no conversationId")
            return
        }
        
        print("🔵 ChatViewModel: Loading messages for conversation: \(conversationId)")
        print("🔵 ChatViewModel: currentUserId: \(currentUserId?.uuidString ?? "nil")")
        
        do {
            // Load all messages by using pagination
            // Start with a large limit to get all messages at once
            var allMessages: [Message] = []
            var skip = 0
            let limit = 100
            var hasMore = true
            
            while hasMore {
                print("🔵 ChatViewModel: Loading messages - skip: \(skip), limit: \(limit)")
                let response = try await conversationService.getMessages(conversationId: conversationId, skip: skip, limit: limit)
                
                guard response.success, let loadedMessages = response.data else {
                    let errorMsg = response.error ?? "Failed to load messages"
                    print("🔵 ChatViewModel: Failed to load messages: \(errorMsg)")
                    break
                }
                
                print("🔵 ChatViewModel: Loaded \(loadedMessages.count) messages from API (skip: \(skip))")
                
                if loadedMessages.isEmpty {
                    hasMore = false
                } else {
                    allMessages.append(contentsOf: loadedMessages)
                    // If we got fewer messages than the limit, we've reached the end
                    if loadedMessages.count < limit {
                        hasMore = false
                    } else {
                        skip += limit
                    }
                }
            }
            
            print("🔵 ChatViewModel: Total messages loaded: \(allMessages.count)")
            
            // Log all messages to see what we received
            for (index, message) in allMessages.enumerated() {
                let isFromCurrentUser = message.senderId == currentUserId
                print("🔵 ChatViewModel: Message \(index):")
                print("   - id: \(message.id)")
                print("   - senderId: \(message.senderId)")
                print("   - senderName: \(message.senderName)")
                print("   - sender object: \(message.sender?.name ?? "nil")")
                print("   - content: \(message.content.prefix(50))")
                print("   - createdAt: \(message.createdAt)")
                print("   - isFromCurrentUser: \(isFromCurrentUser)")
            }
            
            if let currentUserId = currentUserId {
                let displayMessages = allMessages.map { MessageDisplay(from: $0, currentUserId: currentUserId, recipientId: recipientId) }
                let sortedMessages = displayMessages.sorted { $0.timestamp < $1.timestamp }
                await MainActor.run {
                    messages = sortedMessages
                    print("🔵 ChatViewModel: Display messages count: \(messages.count)")
                    print("🔵 ChatViewModel: Messages from current user: \(messages.filter { $0.isFromCurrentUser }.count)")
                    print("🔵 ChatViewModel: Messages from other users: \(messages.filter { !$0.isFromCurrentUser }.count)")
                    print("🔵 ChatViewModel: recipientId: \(recipientId), currentUserId: \(currentUserId)")
                    isLoading = false
                }
            } else {
                print("🔵 ChatViewModel: No currentUserId available")
                await MainActor.run {
                    isLoading = false
                }
            }
        } catch {
            let errorMsg = "Failed to load messages: \(error.localizedDescription)"
            print("🔵 ChatViewModel: Error loading messages: \(errorMsg)")
            await MainActor.run {
                errorMessage = errorMsg
                isLoading = false
            }
        }
    }
    
    private func subscribeToConversation() async {
        guard let conversationId = conversationId else { return }
        
        let subscribeMessage = WebSocketOutgoingMessage(
            type: .subscribe,
            token: nil,
            conversationId: conversationId,
            content: nil,
            forwardedFromId: nil,
            mediaIds: nil,
            messageId: nil,
            sequence: nil
        )
        
        await webSocketService.send(message: subscribeMessage)
    }
    
    // MARK: - WebSocket Handlers
    
    @MainActor
    private func setupWebSocketHandlers() {
        guard let conversationId = conversationId else {
            print("⚠️ ChatViewModel: setupWebSocketHandlers - no conversationId")
            return
        }
        
        print("🔵 ChatViewModel: Setting up WebSocket handlers for conversation \(conversationId)")
        
        // Message handler
        webSocketService.onMessage(conversationId: conversationId) { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self = self, let currentUserId = self.currentUserId else {
                    print("⚠️ ChatViewModel: Handler called but self or currentUserId is nil")
                    return
                }
                
                print("🔵 ChatViewModel: Received message via WebSocket handler")
                print("   - messageId: \(message.id)")
                print("   - senderId: \(message.senderId)")
                print("   - content: \(message.content)")
                print("   - currentUserId: \(currentUserId)")
                print("   - recipientId: \(self.recipientId)")
                print("   - isFromCurrentUser: \(message.senderId == currentUserId)")
                
                let displayMessage = MessageDisplay(from: message, currentUserId: currentUserId, recipientId: self.recipientId)
                
                // Check if message already exists
                if !self.messages.contains(where: { $0.id == displayMessage.id }) {
                    print("🔵 ChatViewModel: Adding new message to list (current count: \(self.messages.count))")
                    self.messages.append(displayMessage)
                    self.messages.sort { $0.timestamp < $1.timestamp }
                    print("🔵 ChatViewModel: Message added, new count: \(self.messages.count)")
                } else {
                    print("⚠️ ChatViewModel: Message already exists in list, skipping")
                }
            }
        }
        
        // Typing handler
        webSocketService.onTyping(conversationId: conversationId) { [weak self] isTyping, userName in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isTyping = isTyping
                self.typingUserName = userName
            }
        }
        
        // User status handler
        webSocketService.onUserStatus(userId: recipientId) { [weak self] isOnline in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isRecipientOnline = isOnline
            }
        }
    }

    // MARK: - Message Management
    
    func sendMessage() {
        guard !newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        let content = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        newMessageText = ""
        
        Task {
            // If no conversationId, create conversation first
            if conversationId == nil {
                await createConversationIfNeeded()
            }
            
            guard let conversationId = conversationId else {
                errorMessage = "Не удалось создать чат. Попробуйте позже."
                return
            }
            
            await sendMessageAsync(content: content, conversationId: conversationId)
        }
    }
    
    @MainActor
    private func createConversationIfNeeded() async {
        do {
            let response = try await conversationService.createConversation(participantIds: [recipientId])
            if response.success, let conversation = response.data {
                conversationId = conversation.id
                // Notify that conversation was created
                NotificationCenter.default.post(name: .conversationCreated, object: nil)
                await subscribeToConversation()
                setupWebSocketHandlers()
                print("🔵 ChatViewModel: Created conversation and set up handlers in createConversationIfNeeded")
            }
        } catch {
            print("Failed to create conversation: \(error)")
        }
    }
    
    @MainActor
    private func sendMessageAsync(content: String, conversationId: UUID) async {
        let message = WebSocketOutgoingMessage(
            type: .message,
            token: nil,
            conversationId: conversationId,
            content: content,
            forwardedFromId: nil,
            mediaIds: nil,
            messageId: nil,
            sequence: nil
        )
        
        await webSocketService.send(message: message)
        
        // Notify that message was sent to update chat list
        NotificationCenter.default.post(name: .messageSent, object: nil)
    }
    
    func startTyping() {
        guard let conversationId = conversationId else { return }
        
        Task {
            let typingMessage = WebSocketOutgoingMessage(
                type: .typingStart,
                token: nil,
                conversationId: conversationId,
                content: nil,
                forwardedFromId: nil,
                mediaIds: nil,
                messageId: nil,
                sequence: nil
            )
            
            await webSocketService.send(message: typingMessage)
        }
    }
    
    func stopTyping() {
        guard let conversationId = conversationId else { return }
        
        Task {
            let typingMessage = WebSocketOutgoingMessage(
                type: .typingStop,
                token: nil,
                conversationId: conversationId,
                content: nil,
                forwardedFromId: nil,
                mediaIds: nil,
                messageId: nil,
                sequence: nil
            )
            
            await webSocketService.send(message: typingMessage)
        }
    }
    
    func markMessageAsRead(messageId: UUID) {
        guard let conversationId = conversationId else { return }
        
        Task {
            let markReadMessage = WebSocketOutgoingMessage(
                type: .markRead,
                token: nil,
                conversationId: conversationId,
                content: nil,
                forwardedFromId: nil,
                mediaIds: nil,
                messageId: messageId,
                sequence: nil
            )
            
            await webSocketService.send(message: markReadMessage)
        }
    }
    
    // MARK: - Cleanup
    
    @MainActor
    func cleanup() {
        guard let conversationId = conversationId else { return }
        
        webSocketService.removeMessageHandler(conversationId: conversationId)
        webSocketService.removeTypingHandler(conversationId: conversationId)
        webSocketService.removeUserStatusHandler(userId: recipientId)
        
        let unsubscribeMessage = WebSocketOutgoingMessage(
            type: .unsubscribe,
            token: nil,
            conversationId: conversationId,
            content: nil,
            forwardedFromId: nil,
            mediaIds: nil,
            messageId: nil,
            sequence: nil
        )
        
        Task {
            await webSocketService.send(message: unsubscribeMessage)
        }
    }
}
