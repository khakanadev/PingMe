import Foundation
import Combine

// MARK: - WebSocket Service
@MainActor
final class WebSocketService: ObservableObject {
    static let shared = WebSocketService()
    
    // MARK: - Published Properties
    @Published var isConnected: Bool = false
    @Published var isAuthenticated: Bool = false
    @Published var currentUserId: UUID?
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    // Production WebSocket endpoint
    private let baseURL = "wss://pingme-messenger.ru/api/v1/ws"
    private var heartbeatTimer: Timer?
    private var reconnectTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var isManualDisconnect = false
    
    // MARK: - Message Handlers
    private var messageHandlers: [UUID: (Message) -> Void] = [:]
    private var typingHandlers: [UUID: (Bool, String) -> Void] = [:]
    private var userStatusHandlers: [UUID: (Bool) -> Void] = [:]
    private var errorHandlers: [(String, String?) -> Void] = []
    
    // For waiting message responses
    private var pendingMessageContinuations: [UUID: CheckedContinuation<UUID?, Error>] = [:]
    
    // MARK: - Initialization
    private init() {}
    
    // MARK: - Connection Management
    
    func connect() async {
        // Reset manual disconnect flag on any explicit connect attempt
        isManualDisconnect = false
        
        // If already connected (e.g. after account switch), always re-authenticate with current token
        if isConnected {
            await authenticate()
            return
        }
        
        guard let url = URL(string: baseURL) else {
            errorMessage = "Invalid WebSocket URL"
            return
        }
        
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        self.urlSession = session
        self.webSocketTask = task
        
        task.resume()
        isConnected = true
        
        // Start receiving messages
        receiveMessages()
        
        // Authenticate if token is available
        await authenticate()
        
        // Start heartbeat
        startHeartbeat()
    }
    
    func disconnect() {
        isManualDisconnect = true
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
        
        isConnected = false
        isAuthenticated = false
        currentUserId = nil
        reconnectAttempts = 0
        
        // Clear handlers to avoid leaking callbacks between accounts
        messageHandlers.removeAll()
        typingHandlers.removeAll()
        userStatusHandlers.removeAll()
        errorHandlers.removeAll()
    }
    
    // MARK: - Authentication
    
    private func authenticate() async {
        guard let token = UserDefaults.standard.string(forKey: "accessToken") else {
            errorMessage = "No access token available"
            return
        }
        
        let authMessage = WebSocketOutgoingMessage(
            type: .auth,
            token: token,
            conversationId: nil,
            content: nil,
            forwardedFromId: nil,
            mediaIds: nil,
            messageId: nil,
            sequence: nil
        )
        
        await send(message: authMessage)
    }
    
    // MARK: - Message Sending
    
    func send(message: WebSocketOutgoingMessage) async {
        guard let task = webSocketTask else {
            errorMessage = "WebSocket not connected"
            return
        }
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(message)
            let jsonString = String(data: data, encoding: .utf8) ?? ""
            
            let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
            try await task.send(wsMessage)
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
        }
    }
    
    /// Send a message and wait for the response to get message_id
    func sendAndWaitForMessageId(message: WebSocketOutgoingMessage, conversationId: UUID, timeout: TimeInterval = 5.0) async throws -> UUID? {
        guard let task = webSocketTask else {
            throw NSError(domain: "WebSocketService", code: -1, userInfo: [NSLocalizedDescriptionKey: "WebSocket not connected"])
        }
        
        guard isAuthenticated else {
            throw NSError(domain: "WebSocketService", code: -2, userInfo: [NSLocalizedDescriptionKey: "WebSocket not authenticated"])
        }
        
        // Generate a unique key for this request
        let requestKey = UUID()
        
        return try await withCheckedThrowingContinuation { continuation in
            // Store continuation
            pendingMessageContinuations[requestKey] = continuation
            
            // Set up timeout
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if let cont = pendingMessageContinuations.removeValue(forKey: requestKey) {
                    cont.resume(returning: nil)
                }
            }
            
            // Send the message
            Task {
                do {
                    let encoder = JSONEncoder()
                    let data = try encoder.encode(message)
                    let jsonString = String(data: data, encoding: .utf8) ?? ""
                    let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
                    try await task.send(wsMessage)
                } catch {
                    pendingMessageContinuations.removeValue(forKey: requestKey)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Message Receiving
    
    private func receiveMessages() {
        guard let task = webSocketTask else { return }
        
        Task {
            do {
                while isConnected {
                    let message = try await task.receive()
                    
                    switch message {
                    case .string(let text):
                        await handleIncomingMessage(text: text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            await handleIncomingMessage(text: text)
                        }
                    @unknown default:
                        break
                    }
                }
            } catch {
                await handleDisconnection()
            }
        }
    }
    
    private func handleIncomingMessage(text: String) async {
        guard let data = text.data(using: .utf8) else { return }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)
                
                let dateFormatter = DateFormatter()
                dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                
                let formats = [
                    "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
                    "yyyy-MM-dd'T'HH:mm:ss.SSSSSZ",
                    "yyyy-MM-dd'T'HH:mm:ss.SSS",
                    "yyyy-MM-dd'T'HH:mm:ss",
                ]
                
                for format in formats {
                    dateFormatter.dateFormat = format
                    if let date = dateFormatter.date(from: dateString) {
                        return date
                    }
                }
                
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Cannot decode date string \(dateString)"
                )
            }
            
            let incomingMessage = try decoder.decode(WebSocketIncomingMessage.self, from: data)
            await processIncomingMessage(incomingMessage)
        } catch {
            // Failed to decode WebSocket message
        }
    }
    
    
    // MARK: - Heartbeat
    
    private func startHeartbeat() {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isConnected else { return }
                let pingMessage = WebSocketOutgoingMessage(
                    type: .ping,
                    token: nil,
                    conversationId: nil,
                    content: nil,
                    forwardedFromId: nil,
                    mediaIds: nil,
                    messageId: nil,
                    sequence: nil
                )
                await self.send(message: pingMessage)
            }
        }
    }
    
    // MARK: - Reconnection
    
    private func handleDisconnection() async {
        isConnected = false
        isAuthenticated = false
        
        // If disconnect was initiated manually (e.g. logout), do NOT auto-reconnect
        if isManualDisconnect {
            return
        }
        
        if reconnectAttempts < maxReconnectAttempts {
            reconnectAttempts += 1
            let delay = Double(reconnectAttempts) * 2.0 // Exponential backoff
            
            reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.connect()
                }
            }
        } else {
            errorMessage = "Failed to reconnect after \(maxReconnectAttempts) attempts"
        }
    }
    
    // MARK: - Helper Methods
    
    private func parseDate(_ dateString: String) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss",
        ]
        
        for format in formats {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: dateString) {
                return date
            }
        }
        
        return nil
    }
}

// MARK: - Message Processing Extension
extension WebSocketService {
    func processIncomingMessage(_ message: WebSocketIncomingMessage) async {
        switch message.type {
        case .authSuccess:
            isAuthenticated = true
            if let userId = message.userId {
                currentUserId = userId
            }
            errorMessage = nil
            
        case .message:
            await handleIncomingMessage(message)
            
        case .typingStart:
            if let conversationId = message.conversationId {
                let userName = message.userName ?? "Someone"
                typingHandlers[conversationId]?(true, userName)
            }
            
        case .typingStop:
            if let conversationId = message.conversationId {
                let userName = message.userName ?? ""
                typingHandlers[conversationId]?(false, userName)
            }
            
        case .userOnline:
            if let userId = message.userId {
                userStatusHandlers[userId]?(true)
            }
            
        case .userOffline:
            if let userId = message.userId {
                userStatusHandlers[userId]?(false)
            }
            
        case .error:
            let code = message.code ?? "UNKNOWN_ERROR"
            let errorMsg = message.message ?? "Unknown error"
            errorMessage = "\(code): \(errorMsg)"
            
            for handler in errorHandlers {
                handler(code, errorMsg)
            }
            
        case .pong:
            break
            
        default:
            break
        }
    }
    
    private func handleIncomingMessage(_ message: WebSocketIncomingMessage) async {
        guard let conversationId = message.conversationId,
              let messageId = message.id,
              let content = message.content,
              let senderId = message.senderId,
              let senderName = message.senderName,
              let createdAtString = message.createdAt,
              let createdAt = parseDate(createdAtString) else {
            return
        }
        
        let updatedAtString = message.updatedAt ?? createdAtString
        let updatedAt = parseDate(updatedAtString) ?? createdAt
        let media = message.media ?? []
        
                // Check if this is a response to a pending message send (from current user)
                // Match by conversationId and senderId to ensure it's our message
                if !pendingMessageContinuations.isEmpty {
                    // If sender is current user, this is likely our sent message
                    if senderId == currentUserId {
                        if let (key, continuation) = pendingMessageContinuations.first(where: { _ in true }) {
                            pendingMessageContinuations.removeValue(forKey: key)
                            continuation.resume(returning: messageId)
                        }
                    }
                }
        
        // Create a minimal User object from WebSocket data
        let sender = User(
            id: senderId,
            email: "",
            name: senderName,
            username: nil,
            phoneNumber: nil,
            isOnline: false,
            isVerified: false,
            authProvider: "",
            mailingMethod: "",
            createdAt: createdAt,
            updatedAt: updatedAt,
            avatarUrl: nil
        )
        
        let wsMessage = Message(
            id: messageId,
            content: content,
            senderId: senderId,
            sender: sender,
            conversationId: conversationId,
            forwardedFromId: message.forwardedFromId,
            media: media,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isEdited: message.isEdited ?? false,
            isDeleted: message.isDeleted ?? false
        )
        
        // Notify handlers
        if let handler = messageHandlers[conversationId] {
            handler(wsMessage)
        }
    }
}

// MARK: - Handlers Registration Extension
extension WebSocketService {
    func onMessage(conversationId: UUID, handler: @escaping (Message) -> Void) {
        messageHandlers[conversationId] = handler
    }
    
    func onTyping(conversationId: UUID, handler: @escaping (Bool, String) -> Void) {
        typingHandlers[conversationId] = handler
    }
    
    func onUserStatus(userId: UUID, handler: @escaping (Bool) -> Void) {
        userStatusHandlers[userId] = handler
    }
    
    func onError(handler: @escaping (String, String?) -> Void) {
        errorHandlers.append(handler)
    }
    
    func removeMessageHandler(conversationId: UUID) {
        messageHandlers.removeValue(forKey: conversationId)
    }
    
    func removeTypingHandler(conversationId: UUID) {
        typingHandlers.removeValue(forKey: conversationId)
    }
    
    func removeUserStatusHandler(userId: UUID) {
        userStatusHandlers.removeValue(forKey: userId)
    }
}

