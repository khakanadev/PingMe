import Foundation

// MARK: - Conversation Service
final class ConversationService {
    // Production API base URL
    private let baseURL = "https://pingme-messenger.ru"
    
    // MARK: - Public Methods
    
    /// Create a new conversation with participants
    func createConversation(participantIds: [UUID], name: String? = nil) async throws -> APIResponse<Conversation> {
        guard let token = UserDefaults.standard.string(forKey: "accessToken") else {
            throw AuthError.serverError("Missing access token")
        }
        
        guard let url = URL(string: "\(baseURL)/api/v1/conversation/") else {
            throw AuthError.invalidURL
        }
        
        // Name is required field (can be null or empty string)
        let requestBody = CreateConversationRequest(participantIds: participantIds, name: name)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        return try await perform(request: request)
    }
    
    /// Get conversation by ID
    func getConversation(id: UUID) async throws -> APIResponse<Conversation> {
        guard let token = UserDefaults.standard.string(forKey: "accessToken") else {
            throw AuthError.serverError("Missing access token")
        }
        
        guard let url = URL(string: "\(baseURL)/api/v1/conversation/\(id.uuidString)") else {
            throw AuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        return try await perform(request: request)
    }
    
    /// Get all conversations for current user
    func getConversations(skip: Int = 0, limit: Int = 50) async throws -> APIResponse<[Conversation]> {
        guard let token = UserDefaults.standard.string(forKey: "accessToken") else {
            throw AuthError.serverError("Missing access token")
        }
        
        guard let url = URL(string: "\(baseURL)/api/v1/conversation/?skip=\(skip)&limit=\(limit)") else {
            throw AuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        return try await perform(request: request)
    }
    
    /// Get messages for a conversation
    func getMessages(conversationId: UUID, skip: Int = 0, limit: Int = 50) async throws -> APIResponse<[Message]> {
        guard let token = UserDefaults.standard.string(forKey: "accessToken") else {
            throw AuthError.serverError("Missing access token")
        }
        
        guard let url = URL(string: "\(baseURL)/api/v1/conversation/messages?conversation_id=\(conversationId.uuidString)&skip=\(skip)&limit=\(limit)") else {
            throw AuthError.invalidURL
        }
        
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        // Log request details for backend debugging
        
        let response: APIResponse<[Message]> = try await perform(request: request)
        
        if let messages = response.data {
            // Log sender IDs to see if we're getting messages from other users
            let senderIds = Set(messages.map { $0.senderId })
            
            
            // Check if we're missing messages from other users
            if let userData = UserDefaults.standard.data(forKey: "userData"),
               let user = try? JSONDecoder().decode(User.self, from: userData) {
                let currentUserId = user.id
                let otherUserMessages = messages.filter { $0.senderId != currentUserId }
                if otherUserMessages.isEmpty && messages.count > 0 {
                }
            }
        } else {
        }
        
        return response
    }
    
    /// Delete a conversation
    func deleteConversation(id: UUID) async throws -> APIResponse<EmptyResponse> {
        guard let token = UserDefaults.standard.string(forKey: "accessToken") else {
            throw AuthError.serverError("Missing access token")
        }
        
        guard let url = URL(string: "\(baseURL)/api/v1/conversation/\(id.uuidString)") else {
            throw AuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        return try await perform(request: request)
    }
    
    /// Find or create a conversation with a user
    func findOrCreateConversation(with userId: UUID) async throws -> APIResponse<Conversation> {
        
        let conversationsResponse = try await getConversations()
        guard let conversations = conversationsResponse.data else {
            return try await attemptCreateConversation(userId: userId)
        }
        
        let dialogConversations = conversations.filter { !$0.isGroup && !$0.isDeleted }
        
        // Try to find by participants first
        if let found = try await findConversationByParticipants(dialogConversations: dialogConversations, userId: userId) {
            return found
        }
        
        // Try to find by messages
        if let found = try await findConversationByMessages(dialogConversations: dialogConversations, userId: userId) {
            return found
        }
        
        // If not found, try to create
        return try await attemptCreateConversation(userId: userId)
    }
    
    // MARK: - Private Helper Methods
    
    private func findConversationByParticipants(dialogConversations: [Conversation], userId: UUID) async throws -> APIResponse<Conversation>? {
        if let existingConversation = dialogConversations.first(where: { conversation in
            guard let participants = conversation.participants, !participants.isEmpty else { return false }
            let hasUser = participants.contains { $0.userId == userId }
            if hasUser {
            }
            return hasUser
        }) {
            return APIResponse(success: true, message: nil, data: existingConversation, error: nil)
        }
        return nil
    }
    
    private func findConversationByMessages(dialogConversations: [Conversation], userId: UUID) async throws -> APIResponse<Conversation>? {
        
        // Get current user ID
        var currentUserId: UUID?
        if let userData = UserDefaults.standard.data(forKey: "userData"),
           let user = try? JSONDecoder().decode(User.self, from: userData) {
            currentUserId = user.id
        }
        
        var conversationsWithOnlyCurrentUser: [(conversation: Conversation, updatedAt: Date)] = []
        
        for conversation in dialogConversations {
            do {
                let messagesResponse = try await getMessages(conversationId: conversation.id, skip: 0, limit: 20)
                guard let messages = messagesResponse.data, !messages.isEmpty else {
                    continue
                }
                
                let senderIds = Set(messages.compactMap { $0.senderId })
                
                // Check if conversation has messages from target user
                if senderIds.contains(userId) {
                    return APIResponse(success: true, message: nil, data: conversation, error: nil)
                }
                
                // If conversation has messages only from current user, it might be the right one
                // (target user hasn't replied yet)
                if let currentUserId = currentUserId,
                   senderIds.count == 1,
                   senderIds.contains(currentUserId) {
                    conversationsWithOnlyCurrentUser.append((conversation: conversation, updatedAt: conversation.updatedAt))
                }
            } catch {
                continue
            }
        }
        
        // If we found conversations with only current user messages, return the most recent one
        // This is a heuristic - if target user hasn't replied, we can't be 100% sure, but it's likely the right one
        if !conversationsWithOnlyCurrentUser.isEmpty {
            let mostRecent = conversationsWithOnlyCurrentUser.max(by: { $0.updatedAt < $1.updatedAt })
            if let mostRecent = mostRecent {
                return APIResponse(success: true, message: nil, data: mostRecent.conversation, error: nil)
            }
        }
        
        return nil
    }
    
    private func attemptCreateConversation(userId: UUID) async throws -> APIResponse<Conversation> {
        
        do {
            let createResponse = try await createConversation(participantIds: [userId])
            if createResponse.success {
                return createResponse
            }
            return try await handleFailedCreation(userId: userId, createResponse: createResponse)
        } catch let error as AuthError {
            if is422Error(error) {
                return try await handle422Error(userId: userId)
            }
            throw error
        } catch {
            throw error
        }
    }
    
    private func handleFailedCreation(userId: UUID, createResponse: APIResponse<Conversation>) async throws -> APIResponse<Conversation> {
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        let conversationsResponse = try await getConversations()
        guard let conversations = conversationsResponse.data else {
            return createResponse
        }
        
        let dialogConversations = conversations.filter { !$0.isGroup && !$0.isDeleted }
        if let found = try await findConversationWithMessages(dialogConversations: dialogConversations) {
            return found
        }
        
        if let mostRecent = dialogConversations.max(by: { $0.updatedAt < $1.updatedAt }) {
            return APIResponse(success: true, message: nil, data: mostRecent, error: nil)
        }
        
        return createResponse
    }
    
    private func handle422Error(userId: UUID) async throws -> APIResponse<Conversation> {
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        let conversationsResponse = try await getConversations()
        guard let conversations = conversationsResponse.data else {
            throw AuthError.serverError("Failed to reload conversations after 422")
        }
        
        let dialogConversations = conversations.filter { !$0.isGroup && !$0.isDeleted }
        
        // Get current user ID
        var currentUserId: UUID?
        if let userData = UserDefaults.standard.data(forKey: "userData"),
           let user = try? JSONDecoder().decode(User.self, from: userData) {
            currentUserId = user.id
        }
        
        // Try to find conversation with messages only from current user (target user hasn't replied yet)
        var candidates: [(conversation: Conversation, updatedAt: Date)] = []
        
        for conversation in dialogConversations {
            do {
                let messagesResponse = try await getMessages(conversationId: conversation.id, skip: 0, limit: 1)
                if let messages = messagesResponse.data, !messages.isEmpty {
                    let senderIds = Set(messages.compactMap { $0.senderId })
                    // If conversation has messages only from current user, it might be the right one
                    if let currentUserId = currentUserId,
                       senderIds.count == 1,
                       senderIds.contains(currentUserId) {
                        candidates.append((conversation: conversation, updatedAt: conversation.updatedAt))
                    }
                }
            } catch {
                continue
            }
        }
        
        // Return the most recent candidate
        if let mostRecent = candidates.max(by: { $0.updatedAt < $1.updatedAt }) {
            return APIResponse(success: true, message: nil, data: mostRecent.conversation, error: nil)
        }
        
        // If no candidates, return the most recent dialog conversation
        if let mostRecent = dialogConversations.max(by: { $0.updatedAt < $1.updatedAt }) {
            return APIResponse(success: true, message: nil, data: mostRecent, error: nil)
        }
        
        throw AuthError.serverError("Could not find existing conversation after 422")
    }
    
    private func findConversationWithMessages(dialogConversations: [Conversation]) async throws -> APIResponse<Conversation>? {
        for conversation in dialogConversations {
            do {
                let messagesResponse = try await getMessages(conversationId: conversation.id, skip: 0, limit: 1)
                if let messages = messagesResponse.data, !messages.isEmpty {
                    return APIResponse(success: true, message: nil, data: conversation, error: nil)
                }
            } catch {
                continue
            }
        }
        return nil
    }
    
    private func is422Error(_ error: AuthError) -> Bool {
        if case .serverError(let message) = error {
            return message.contains("422") || message.contains("already exists") || message.contains("Conversation already exists")
        }
        return false
    }
    
    // MARK: - Private Methods
    
    private func perform<T: Codable>(request: URLRequest) async throws -> APIResponse<T> {
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        
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
        
        if httpResponse.statusCode >= 400 {
            // Special handling for 422 (Unprocessable Entity) - conversation might already exist
            if httpResponse.statusCode == 422 {
                if let errorResponse = try? JSONDecoder().decode(APIResponse<EmptyResponse>.self, from: data) {
                    throw AuthError.serverError("422: \(errorResponse.error ?? "Conversation already exists")")
                }
                throw AuthError.serverError("HTTP 422: Conversation already exists")
            }
            if let errorResponse = try? JSONDecoder().decode(APIResponse<EmptyResponse>.self, from: data) {
                throw AuthError.serverError(errorResponse.error ?? "Server error")
            }
            throw AuthError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        // Log raw response for debugging (especially for getMessages)
        if let responseString = String(data: data, encoding: .utf8) {
            if responseString.count < 5000 {
            } else {
            }
        }
        
        do {
            let apiResponse = try decoder.decode(APIResponse<T>.self, from: data)
            return apiResponse
        } catch {
            if let responseString = String(data: data, encoding: .utf8) {
            }
            throw AuthError.decodingError
        }
    }
}

// MARK: - Empty Response
struct EmptyResponse: Codable {}

