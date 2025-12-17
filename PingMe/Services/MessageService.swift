import Foundation

// MARK: - Message Service
final class MessageService {
    private let baseURL = "https://pingme-messenger.ru"
    
    // MARK: - Public Methods
    
    /// Edit an existing message
    func editMessage(messageId: UUID, content: String) async throws -> APIResponse<Message> {
        guard let token = UserDefaults.standard.string(forKey: "accessToken") else {
            throw AuthError.serverError("Missing access token")
        }
        
        guard let url = URL(string: "\(baseURL)/api/v1/messages/\(messageId.uuidString)") else {
            throw AuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = MessageEditRequest(content: content)
        request.httpBody = try JSONEncoder().encode(body)
        
        return try await perform(request: request)
    }
    
    /// Delete a message
    func deleteMessage(messageId: UUID) async throws -> APIResponse<Message> {
        guard let token = UserDefaults.standard.string(forKey: "accessToken") else {
            throw AuthError.serverError("Missing access token")
        }
        
        guard let url = URL(string: "\(baseURL)/api/v1/messages/\(messageId.uuidString)") else {
            throw AuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        return try await perform(request: request)
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
            if let serverMessage = String(data: data, encoding: .utf8) {
                throw AuthError.serverError(serverMessage)
            }
            throw AuthError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        do {
            let apiResponse = try decoder.decode(APIResponse<T>.self, from: data)
            return apiResponse
        } catch {
            throw AuthError.decodingError
        }
    }
}

// MARK: - Requests
private struct MessageEditRequest: Codable {
    let content: String
}


