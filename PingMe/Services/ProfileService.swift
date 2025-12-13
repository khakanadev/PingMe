import Foundation
import UIKit

// MARK: - Media Response Model
struct MediaResponse: Codable {
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
        case url
        case size
        case messageId = "message_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Profile Service
final class ProfileService {
    private let baseURL = "http://localhost:8000"
    private struct DetailWrapper<R: Codable>: Codable {
        let detail: APIResponse<R>
    }

    // MARK: - Request Models
    struct UserUpdateRequest: Codable {
        let name: String?
        let username: String?
        let phoneNumber: String?

        enum CodingKeys: String, CodingKey {
            case name
            case username
            case phoneNumber = "phone_number"
        }
    }

    // MARK: - Public
    func searchUsers(query: String, skip: Int = 0, limit: Int = 50) async throws -> APIResponse<[UserBrief]> {
        guard let token = UserDefaults.standard.string(forKey: "accessToken") else {
            throw AuthError.serverError("Missing access token")
        }
        
        guard let url = URL(string: "\(baseURL)/api/v1/users/search?query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)&skip=\(skip)&limit=\(limit)") else {
            throw AuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        return try await perform(request: request)
    }
    
    func fetchProfile() async throws -> APIResponse<User> {
        guard let token = UserDefaults.standard.string(forKey: "accessToken") else {
            throw AuthError.serverError("Missing access token")
        }
        
        var request = try authorizedRequest(endpoint: "/api/v1/users/me", method: "GET")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        return try await perform(request: request)
    }
    
    /// Get user by ID - returns UserBrief (simplified user info)
    func getUserById(_ userId: UUID) async throws -> APIResponse<UserBrief> {
        guard let token = UserDefaults.standard.string(forKey: "accessToken") else {
            throw AuthError.serverError("Missing access token")
        }
        
        var request = try authorizedRequest(endpoint: "/api/v1/users/\(userId.uuidString)", method: "GET")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("🔵 ProfileService: Getting user by ID: \(userId.uuidString)")
        let response: APIResponse<UserBrief> = try await perform(request: request)
        print("🔵 ProfileService: getUserById response - success: \(response.success), data: \(response.data != nil ? "present" : "nil")")
        return response
    }

    func updateProfile(
        name: String,
        username: String,
        phoneNumber: String?
    ) async throws -> APIResponse<User> {
        guard let token = UserDefaults.standard.string(forKey: "accessToken") else {
            throw AuthError.serverError("Missing access token")
        }

        let trimmedPhone = phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        let phoneToSend = trimmedPhone?.isEmpty == false ? trimmedPhone : nil

        let requestBody = UserUpdateRequest(
            name: name,
            username: username,
            phoneNumber: phoneToSend
        )

        var request = try authorizedRequest(endpoint: "/api/v1/users/me", method: "PATCH")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        return try await perform(request: request)
    }

    func uploadAvatar(_ image: UIImage) async throws -> APIResponse<MediaResponse> {
        guard let token = UserDefaults.standard.string(forKey: "accessToken") else {
            throw AuthError.serverError("Missing access token")
        }

        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            throw AuthError.serverError("Failed to convert image to data")
        }

        let boundary = UUID().uuidString
        var request = try authorizedRequest(
            endpoint: "/api/v1/users/me/avatar",
            method: "POST",
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var body = Data()
        body.appendMultipartData(
            name: "file",
            filename: "avatar.jpg",
            mimeType: "image/jpeg",
            data: imageData,
            boundary: boundary
        )
        body.appendString("--\(boundary)--\r\n")
        request.httpBody = body

        return try await perform(request: request)
    }

    // MARK: - Internal helpers
    private func performRequest<T: Codable>(
        endpoint: String,
        method: String,
        body: T? = nil
    ) async throws -> APIResponse<User> {
        var request = try authorizedRequest(endpoint: endpoint, method: method)
        
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        
        return try await perform(request: request)
    }

    private func authorizedRequest(
        endpoint: String,
        method: String,
        contentType: String? = nil
    ) throws -> URLRequest {
        guard let url = URL(string: baseURL + endpoint) else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        
        return request
    }

    private func perform<R: Codable>(request: URLRequest) async throws -> APIResponse<R> {
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

        // Unauthorized -> ask to re-login
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw AuthError.serverError("Сессия истекла. Войдите снова.")
        }

        // Check HTTP status code first
        if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
            // Try decoding standard APIResponse first
            if let apiResponse = try? decoder.decode(APIResponse<R>.self, from: data) {
                print("🔵 ProfileService: Successfully decoded APIResponse")
                return apiResponse
            }

            // Try decoding raw model and wrap it
            if let model = try? decoder.decode(R.self, from: data) {
                print("🔵 ProfileService: Successfully decoded raw model")
                return APIResponse(success: true, message: nil, data: model, error: nil)
            }

            // Try detail wrapper from backend
            if let wrapped = try? decoder.decode(DetailWrapper<R>.self, from: data) {
                print("🔵 ProfileService: Successfully decoded DetailWrapper")
                return wrapped.detail
            }
            
            // If all decoding attempts failed, log the raw response
            if let responseString = String(data: data, encoding: .utf8) {
                print("🔵 ProfileService: Failed to decode response. Raw data: \(responseString)")
            }
        } else {
            // Non-2xx status code - try to decode error message
            if let responseString = String(data: data, encoding: .utf8) {
                print("🔵 ProfileService: HTTP \(httpResponse.statusCode) error: \(responseString)")
                throw AuthError.serverError("HTTP \(httpResponse.statusCode): \(responseString)")
            }
        }

        // Try to surface server error text if present
        if let serverMessage = String(data: data, encoding: .utf8) {
            throw AuthError.serverError(serverMessage)
        }

        throw AuthError.decodingError
    }
}

// MARK: - Multipart helpers
private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendMultipartData(
        name: String,
        filename: String,
        mimeType: String,
        data: Data,
        boundary: String
    ) {
        appendString("--\(boundary)\r\n")
        appendString(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
        )
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        append(data)
        appendString("\r\n")
    }
}
