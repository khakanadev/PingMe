import Foundation

// MARK: - Error Types
enum AuthError: Error {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError
    case serverError(String)
}

// MARK: - Auth Service
class AuthService {
    // Production API base URL
    private let baseURL = "https://pingme-messenger.ru"

    // MARK: - Public Methods
    func register(email: String, password: String, name: String) async throws -> APIResponse<
        RegisterResponseData
    > {
        let request = RegisterRequest(email: email, password: password, name: name)
        return try await performRequest(endpoint: "/api/v1/auth/register", body: request)
    }

    func verifyRegistration(email: String, password: String, token: String) async throws
        -> APIResponse<VerifyResponseData> {
        let request = VerifyRegistrationRequest(email: email, password: password, token: token)
        return try await performRequest(endpoint: "/api/v1/auth/verify-registration", body: request)
    }

    func login(email: String, password: String) async throws -> APIResponse<RegisterResponseData> {
        let request = LoginRequest(email: email, password: password)
        return try await performRequest(endpoint: "/api/v1/auth/login", body: request)
    }

    func verifyLogin(email: String, password: String, token: String) async throws -> APIResponse<
        VerifyResponseData
    > {
        let request = VerifyLoginRequest(email: email, password: password, token: token)
        return try await performRequest(endpoint: "/api/v1/auth/verify-login", body: request)
    }

    // MARK: - Private Methods
    private func performRequest<T: Codable, R: Codable>(endpoint: String, body: T) async throws
        -> APIResponse<R> {
        guard let url = URL(string: baseURL + endpoint) else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if httpResponse.statusCode == 422 {
            let errorResponse = try JSONDecoder().decode(ValidationErrorResponse.self, from: data)
            throw AuthError.serverError(errorResponse.detail.first?.msg ?? "Validation error")
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

        do {
            return try decoder.decode(APIResponse<R>.self, from: data)
        } catch {
            throw AuthError.decodingError
        }
    }
}

// MARK: - Supporting Types
struct ValidationErrorDetail: Codable {
    let loc: [String]
    let msg: String
    let type: String
}

struct ValidationErrorResponse: Codable {
    let detail: [ValidationErrorDetail]
}
