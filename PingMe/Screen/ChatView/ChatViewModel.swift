// swiftlint:disable type_body_length cyclomatic_complexity line_length
import Foundation
import Combine
import UIKit

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
    @Published var attachments: [AttachmentItem] = []
    @Published var isSending: Bool = false
    @Published var hasMoreMessages: Bool = true
    @Published var isLoadingOlderMessages: Bool = false
    @Published var unreadMessageCount: Int = 0
    @Published var isAtBottom: Bool = true
    
    // MARK: - Private Properties
    private let conversationService = ConversationService()
    private let webSocketService = WebSocketService.shared
    private let mediaService = MediaService()
    private var currentUserId: UUID?
    private var isInitializing = false // Prevent multiple initializations
    private let messagesPerPage = 50
    private var oldestLoadedMessageId: UUID?
    private var totalMessagesLoaded: Int = 0

    // MARK: - Initialization
    init(recipientId: UUID, recipientName: String, recipientUsername: String? = nil, recipientAvatarUrl: String? = nil, isRecipientOnline: Bool = true, conversationId: UUID? = nil) {
        self.recipientId = recipientId
        // Ensure recipientName is never empty - use fallback if needed
        self.recipientName = recipientName.isEmpty ? "Пользователь" : recipientName
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
            return
        }
        isInitializing = true
        defer { 
            isInitializing = false
        }
        
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
    }
    
    // MARK: - Conversation Management
    
    private func findOrCreateConversation() async {
        
        // Prevent multiple simultaneous calls
        guard conversationId == nil else {
            return
        }
        
        do {
            // First, try to find existing conversation
            let conversationsResponse = try await conversationService.getConversations()
            
            if let conversations = conversationsResponse.data,
               let existingConversation = conversations.first(where: { conversation in
                   !conversation.isGroup && conversation.participants?.contains { $0.userId == recipientId } == true
               }) {
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
            let response = try await conversationService.createConversation(participantIds: [recipientId])
            
            if response.success, let conversation = response.data {
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
                // Allow user to send message anyway - conversation will be created via WebSocket
                await MainActor.run {
                    errorMessage = nil
                    isLoading = false
                }
            }
        } catch {
            // On error, still allow sending message
            await MainActor.run {
                errorMessage = nil
                isLoading = false
            }
        }
    }
    
    private func loadMessages() async {
        guard let conversationId = conversationId else {
            return
        }
        
        do {
            // First, load a batch to determine total count, then load last 50
            // Start by loading first batch
            var allMessages: [Message] = []
            var skip = 0
            let batchSize = 100
            var hasMore = true
            
            // Load in batches until we have enough or reach the end
            while hasMore && allMessages.count < messagesPerPage * 2 {
                let response = try await conversationService.getMessages(
                    conversationId: conversationId,
                    skip: skip,
                    limit: batchSize
                )
                
                guard response.success, let loadedMessages = response.data else {
                    break
                }
                
                if loadedMessages.isEmpty {
                    hasMore = false
                } else {
                    allMessages.append(contentsOf: loadedMessages)
                    if loadedMessages.count < batchSize {
                        hasMore = false
                    } else {
                        skip += batchSize
                    }
                }
            }
            
            // Take only the last messagesPerPage messages
            let lastMessages = Array(allMessages.suffix(messagesPerPage))
            
            if let currentUserId = currentUserId {
                let displayMessages = lastMessages.map { MessageDisplay(from: $0, currentUserId: currentUserId, recipientId: recipientId) }
                let sortedMessages = displayMessages.sorted { $0.timestamp < $1.timestamp }
                
                await MainActor.run {
                    messages = sortedMessages
                    hasMoreMessages = allMessages.count >= messagesPerPage
                    totalMessagesLoaded = sortedMessages.count
                    if let oldestMessage = sortedMessages.first {
                        oldestLoadedMessageId = oldestMessage.id
                    }
                    isLoading = false
                }
            } else {
                await MainActor.run {
                    isLoading = false
                }
            }
        } catch {
            let errorMsg = "Failed to load messages: \(error.localizedDescription)"
            await MainActor.run {
                errorMessage = errorMsg
                isLoading = false
            }
        }
    }
    
    /// Load older messages (pagination when scrolling up)
    func loadOlderMessages() async {
        guard let conversationId = conversationId,
              hasMoreMessages,
              !isLoadingOlderMessages,
              let oldestId = oldestLoadedMessageId else {
            return
        }
        
        await MainActor.run {
            isLoadingOlderMessages = true
        }
        
        do {
            // Load older messages by loading from skip = 0
            // We'll load messages in batches until we have enough older messages
            var allMessages: [Message] = []
            var skip = 0
            let batchSize = 100
            var hasMore = true
            var foundCurrentOldest = false
            
            // Load messages until we find our current oldest message or have enough
            while hasMore && !foundCurrentOldest && allMessages.count < totalMessagesLoaded + messagesPerPage * 2 {
                let response = try await conversationService.getMessages(
                    conversationId: conversationId,
                    skip: skip,
                    limit: batchSize
                )
                
                guard response.success, let loadedMessages = response.data else {
                    break
                }
                
                if loadedMessages.isEmpty {
                    hasMore = false
                    break
                }
                
                // Check if we've found our current oldest message
                for message in loadedMessages {
                    if message.id == oldestId {
                        foundCurrentOldest = true
                        // Don't include this message, it's already loaded
                        break
                    }
                    allMessages.append(message)
                }
                
                if loadedMessages.count < batchSize {
                    hasMore = false
                } else {
                    skip += batchSize
                }
            }
            
            // Take only the messagesPerPage most recent older messages (those closest to our current oldest)
            let olderMessages = Array(allMessages.suffix(messagesPerPage))
            
            if let currentUserId = currentUserId {
                let displayMessages = olderMessages.map { MessageDisplay(from: $0, currentUserId: currentUserId, recipientId: recipientId) }
                let sortedMessages = displayMessages.sorted { $0.timestamp < $1.timestamp }
                
                await MainActor.run {
                    // Insert older messages at the beginning
                    let combinedMessages = sortedMessages + messages
                    let uniqueMessages = Array(Set(combinedMessages.map { $0.id }))
                        .compactMap { id in combinedMessages.first(where: { $0.id == id }) }
                        .sorted { $0.timestamp < $1.timestamp }
                    
                    messages = uniqueMessages
                    totalMessagesLoaded = uniqueMessages.count
                    hasMoreMessages = !foundCurrentOldest || allMessages.count >= messagesPerPage
                    if let oldestMessage = uniqueMessages.first {
                        oldestLoadedMessageId = oldestMessage.id
                    }
                    isLoadingOlderMessages = false
                }
            } else {
                await MainActor.run {
                    isLoadingOlderMessages = false
                }
            }
        } catch {
            await MainActor.run {
                isLoadingOlderMessages = false
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
            return
        }
        
        
        // Message handler
        webSocketService.onMessage(conversationId: conversationId) { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self = self, let currentUserId = self.currentUserId else {
                    return
                }
                
                
                let displayMessage = MessageDisplay(from: message, currentUserId: currentUserId, recipientId: self.recipientId)
                
                // Check if message already exists
                if !self.messages.contains(where: { $0.id == displayMessage.id }) {
                    self.messages.append(displayMessage)
                    self.messages.sort { $0.timestamp < $1.timestamp }
                    
                    // If user is not at bottom, increment unread count
                    if !self.isAtBottom {
                        self.unreadMessageCount += 1
                    }
                } else {
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
        // Prevent double sending
        guard !isSending else {
            return
        }
        
        let trimmed = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasText = !trimmed.isEmpty
        let hasAttachments = !attachments.isEmpty
        
        guard hasText || hasAttachments else {
            return
        }
        
        isSending = true
        newMessageText = ""
        
        Task {
            defer {
                Task { @MainActor in
                    self.isSending = false
                }
            }
            
            // If no conversationId, create conversation first
            if conversationId == nil {
                await createConversationIfNeeded()
            }
            
            guard let conversationId = conversationId else {
                errorMessage = "Не удалось создать чат. Попробуйте позже."
                return
            }
            
            await sendMessageAsync(content: trimmed, conversationId: conversationId)
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
            }
        } catch {
        }
    }
    
    @MainActor
    private func sendMessageAsync(content: String, conversationId: UUID) async {
        
        // Step 1: Send message first (without media) to get message_id
        let message = WebSocketOutgoingMessage(
            type: .message,
            token: nil,
            conversationId: conversationId,
            content: content.isEmpty ? " " : content, // Send at least space if no text
            forwardedFromId: nil,
            mediaIds: nil, // Will upload media after getting message_id
            messageId: nil,
            sequence: nil
        )
        
        // Send message and wait for message_id if we have attachments
        if !attachments.isEmpty {
            let attachmentsCount = attachments.count
            do {
                let messageId = try await webSocketService.sendAndWaitForMessageId(
                    message: message,
                    conversationId: conversationId,
                    timeout: 5.0
                )
                
                if let msgId = messageId {
                    // Step 2: Upload media with the received message_id
                    do {
                        let mediaIds = try await uploadAttachments(conversationId: conversationId, messageId: msgId)
                        
                        // Step 3: Reload the message from API to get updated media
                        await reloadMessage(messageId: msgId)
                        
                        // Clear attachments after successful upload
                        await MainActor.run {
                            self.attachments.removeAll()
                        }
                    } catch {
                        // Clear attachments even on error to prevent infinite loading
                        await MainActor.run {
                            self.attachments.removeAll()
                            self.errorMessage = "Сообщение отправлено, но не удалось загрузить вложения: \(self.describe(error))"
                        }
                    }
                } else {
                    // Clear attachments on timeout to prevent infinite loading
                    await MainActor.run {
                        self.attachments.removeAll()
                        self.errorMessage = "Сообщение отправлено, но не удалось получить ID сообщения для загрузки вложений. Попробуйте отправить сообщение еще раз."
                    }
                }
            } catch {
                // Clear attachments on error
                await MainActor.run {
                    self.attachments.removeAll()
                    self.errorMessage = "Не удалось отправить сообщение: \(self.describe(error))"
                }
                return
            }
        } else {
            // No attachments, just send the message
            await webSocketService.send(message: message)
        }
        
        // Notify that message was sent to update chat list
        NotificationCenter.default.post(name: .messageSent, object: nil)
    }

    // MARK: - Attachments
    func addAttachment(_ image: UIImage) {
        let item = AttachmentItem(image: image, state: .pending)
        attachments.append(item)
    }
    
    func removeAttachment(id: UUID) {
        attachments.removeAll { $0.id == id }
    }
    
    private func uploadAttachments(conversationId: UUID, messageId: UUID?) async throws -> [UUID] {
        var result: [UUID] = []
        let attachmentsToUpload = attachments // Copy to avoid index issues
        
        for (index, attachment) in attachmentsToUpload.enumerated() {
            let id = attachment.id
            await MainActor.run {
                if index < attachments.count {
                    attachments[index].state = .uploading
                }
            }
            do {
                let messageIdStr = messageId?.uuidString ?? "nil"
                let response = try await mediaService.uploadMedia(
                    image: attachment.image,
                    conversationId: conversationId,
                    messageId: messageId
                )
                if response.success, let mediaArray = response.data, let firstMedia = mediaArray.first {
                    result.append(firstMedia.id)
                    await MainActor.run {
                        if index < attachments.count {
                            attachments[index].state = .uploaded(firstMedia.id)
                        }
                    }
                } else {
                    let errMsg = response.error ?? response.message ?? "Не удалось загрузить файл"
                    if let data = response.data {
                    }
                    await MainActor.run {
                        if index < attachments.count {
                            attachments[index].state = .failed(errMsg)
                        }
                    }
                    throw AuthError.serverError(errMsg)
                }
            } catch {
                await MainActor.run {
                    if index < attachments.count {
                        attachments[index].state = .failed(error.localizedDescription)
                    }
                }
                throw error
            }
        }
        // Don't clear attachments here - let sendMessageAsync do it after all operations complete
        return result
    }
    
    /// Reload a specific message from API to get updated media
    @MainActor
    private func reloadMessage(messageId: UUID) async {
        guard let conversationId = conversationId, let currentUserId = currentUserId else {
            return
        }
        
        
        do {
            // Reload all messages to get the updated one
            let response = try await conversationService.getMessages(conversationId: conversationId, skip: 0, limit: 100)
            
            guard response.success, let allMessages = response.data else {
                return
            }
            
            // Find the updated message
            if let updatedMessage = allMessages.first(where: { $0.id == messageId }) {
                
                // Update the message in the list
                if let index = messages.firstIndex(where: { $0.id == messageId }) {
                    let updatedDisplayMessage = MessageDisplay(from: updatedMessage, currentUserId: currentUserId, recipientId: recipientId)
                    messages[index] = updatedDisplayMessage
                    messages.sort { $0.timestamp < $1.timestamp }
                } else {
                    let updatedDisplayMessage = MessageDisplay(from: updatedMessage, currentUserId: currentUserId, recipientId: recipientId)
                    messages.append(updatedDisplayMessage)
                    messages.sort { $0.timestamp < $1.timestamp }
                }
            } else {
            }
        } catch {
        }
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
    
    // MARK: - Scroll Position Management
    
    func saveScrollPosition(messageId: UUID?) {
        guard let conversationId = conversationId, let messageId = messageId else { return }
        let key = "scroll_position_\(conversationId.uuidString)"
        UserDefaults.standard.set(messageId.uuidString, forKey: key)
    }
    
    func getSavedScrollPosition() -> UUID? {
        guard let conversationId = conversationId else { return nil }
        let key = "scroll_position_\(conversationId.uuidString)"
        if let messageIdString = UserDefaults.standard.string(forKey: key),
           let messageId = UUID(uuidString: messageIdString) {
            return messageId
        }
        return nil
    }
    
    func clearScrollPosition() {
        guard let conversationId = conversationId else { return }
        let key = "scroll_position_\(conversationId.uuidString)"
        UserDefaults.standard.removeObject(forKey: key)
    }
    
    func markAsRead() {
        unreadMessageCount = 0
    }

    // MARK: - Error description
    private func describe(_ error: Error) -> String {
        guard let authError = error as? AuthError else {
            return error.localizedDescription
        }
        
        switch authError {
        case .serverError(let message):
            return message
        case .decodingError:
            return "Ошибка разбора ответа сервера"
        case .invalidURL:
            return "Некорректный адрес запроса"
        case .invalidResponse:
            return "Некорректный ответ сервера"
        @unknown default:
            return error.localizedDescription
        }
    }
}

// MARK: - Attachment Item
struct AttachmentItem: Identifiable, Hashable {
    let id: UUID = UUID()
    let image: UIImage
    var state: AttachmentState
    
    static func == (lhs: AttachmentItem, rhs: AttachmentItem) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum AttachmentState: Hashable {
    case pending
    case uploading
    case uploaded(UUID)
    case failed(String)
}
