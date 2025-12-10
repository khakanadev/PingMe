import Foundation

struct User: Codable {
    let id: UUID
    let email: String
    let name: String
    let username: String?
    let phoneNumber: String?
    let isOnline: Bool
    let isVerified: Bool
    let authProvider: String
    let mailingMethod: String
    let createdAt: Date
    let updatedAt: Date
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, email, name, username
        case phoneNumber = "phone_number"
        case isOnline = "is_online"
        case isVerified = "is_verified"
        case authProvider = "auth_provider"
        case mailingMethod = "mailing_method"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case avatarUrl = "avatar_url"
    }
}
