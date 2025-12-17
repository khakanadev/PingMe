import Foundation

// MARK: - Token Service
final class TokenService {
    private let baseURL = "https://pingme-messenger.ru"
    
    // MARK: - Public API
    
    /// Check stored tokens and try to refresh access token if needed.
    /// Returns `true` if user should be considered authenticated after this check.
    func ensureValidSession() async -> Bool {
        guard let accessToken = UserDefaults.standard.string(forKey: "accessToken"),
              let refreshToken = UserDefaults.standard.string(forKey: "refreshToken") else {
            return false
        }
        
        let now = Date().timeIntervalSince1970
        let accessExp = UserDefaults.standard.double(forKey: "accessTokenExpiration")
        let refreshExp = UserDefaults.standard.double(forKey: "refreshTokenExpiration")
        
        // If refresh token already expired – consider session invalid
        if refreshExp > 0, now >= refreshExp {
            clearTokens()
            return false
        }
        
        // If access token is still valid – session is ok
        if accessExp > 0, now < accessExp {
            return true
        }
        
        // Access token expired but refresh is still valid – try to refresh
        do {
            let newTokens = try await refreshTokens(refreshToken: refreshToken)
            storeTokens(tokens: newTokens)
            return true
        } catch let error as AuthError {
            // Logout only if backend явно сказал, что refresh недействителен (403/401)
            if case .serverError(let message) = error,
               message.contains("403") || message.contains("401") {
                clearTokens()
                return false
            }
            // Any other error (сетевые проблемы, временные ошибки) – оставляем старые токены
            return true
        } catch {
            // Неизвестная ошибка – не ломаем сессию, позволяем запросам самим отловить 401/403
            return true
        }
    }
    
    // MARK: - Refresh Logic
    
    private func refreshTokens(refreshToken: String) async throws -> Tokens {
        guard let url = URL(string: "\(baseURL)/api/v1/auth/refresh") else {
            throw AuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["refresh_token": refreshToken]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        
        if httpResponse.statusCode == 403 {
            // Refresh forbidden – session is invalid
            throw AuthError.serverError("403")
        }
        
        if httpResponse.statusCode >= 400 {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw AuthError.serverError(message)
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
        
        struct RefreshResponse: Codable {
            let tokens: Tokens
        }
        
        let apiResponse = try decoder.decode(APIResponse<RefreshResponse>.self, from: data)
        guard apiResponse.success, let tokens = apiResponse.data?.tokens else {
            throw AuthError.serverError(apiResponse.error ?? "Failed to refresh token")
        }
        
        return tokens
    }
    
    // MARK: - Storage
    
    func storeTokens(tokens: Tokens) {
        UserDefaults.standard.set(tokens.access.token, forKey: "accessToken")
        UserDefaults.standard.set(tokens.refresh.token, forKey: "refreshToken")
        UserDefaults.standard.set(
            tokens.access.expiresAt.timeIntervalSince1970,
            forKey: "accessTokenExpiration"
        )
        UserDefaults.standard.set(
            tokens.refresh.expiresAt.timeIntervalSince1970,
            forKey: "refreshTokenExpiration"
        )
        UserDefaults.standard.synchronize()
    }
    
    func clearTokens() {
        UserDefaults.standard.removeObject(forKey: "accessToken")
        UserDefaults.standard.removeObject(forKey: "refreshToken")
        UserDefaults.standard.removeObject(forKey: "accessTokenExpiration")
        UserDefaults.standard.removeObject(forKey: "refreshTokenExpiration")
        UserDefaults.standard.synchronize()
    }
}


