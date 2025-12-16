import Combine
import Foundation
import SwiftUI

@Observable
class EditProfileViewModel {
    private let profileService = ProfileService()

    var name: String = "Name"
    var username: String = "username"
    var phoneNumber: String = "+7 (900) 900 90 90"
    var profileImage: UIImage?
    var avatarUrl: String?
    var isSlideBarShowing: Bool = false
    var isLoading: Bool = false
    var isSaving: Bool = false
    var errorMessage: String?
    var isValidUsername: Bool = true
    var usernameErrorMessage: String = ""

    init() {
        loadUserData()
        Task {
            await fetchProfile()
        }
    }

    func updatePhoneNumber(_ newNumber: String) {
        phoneNumber = newNumber
    }

    func updateUsername(_ newUsername: String) {
        username = newUsername
        validateUsername()
    }

    func validateUsername() {
        // Check if username contains any non-ASCII letters (Russian, etc.)
        let hasNonEnglish = username.contains { char in
            char.isLetter && !char.isASCII
        }
        
        // Only allow English letters (A-Z, a-z), numbers (0-9), and underscore
        let usernameRegex = "^[A-Za-z0-9_]+$"
        let usernamePredicate = NSPredicate(format: "SELF MATCHES %@", usernameRegex)
        
        isValidUsername = !hasNonEnglish && usernamePredicate.evaluate(with: username)
        usernameErrorMessage = isValidUsername ? "" : "Username может содержать только английские буквы, цифры и символ подчеркивания"
    }

    func updateName(_ newName: String) {
        name = newName
    }

    func updateProfileImage(_ image: UIImage) {
        profileImage = image
    }

    @MainActor
    func saveChanges() async {
        errorMessage = nil
        validateUsername()
        
        guard isValidUsername else {
            errorMessage = usernameErrorMessage
            return
        }
        
        isSaving = true
        defer { isSaving = false }
        do {
            // First update profile data (name, username, phone)
            let trimmedPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            let phoneToSend = trimmedPhone.isEmpty ? nil : trimmedPhone

            let response = try await profileService.updateProfile(
                name: name,
                username: username,
                phoneNumber: phoneToSend
            )

            guard response.success, let user = response.data else {
                errorMessage = response.error ?? "Не удалось сохранить профиль"
                return
            }

            persist(user: user)

            // Then upload avatar separately if provided
            if let image = profileImage {
                do {
                    let avatarResponse = try await profileService.uploadAvatar(image)
                    if avatarResponse.success {
                        // Avatar uploaded successfully, fetch updated user profile
                        let updatedProfileResponse = try await profileService.fetchProfile()
                        if updatedProfileResponse.success, let updatedUser = updatedProfileResponse.data {
                            persist(user: updatedUser)
                            apply(updatedUser)
                            // Clear local image to show loaded avatar from URL
                            profileImage = nil
                        }
                    } else {
                        // Only show error if upload failed
                        errorMessage = avatarResponse.error ?? "Не удалось загрузить аватар"
                        return
                    }
                } catch {
                    // If avatar upload fails, don't block the whole save operation
                    // Just log the error but continue
                    // Don't set errorMessage here - profile was saved successfully
                }
            }

            NotificationCenter.default.post(name: .userDataUpdated, object: nil)
        } catch AuthError.serverError(let message) {
            errorMessage = message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func fetchProfile() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await profileService.fetchProfile()
            guard response.success, let user = response.data else {
                errorMessage = response.error ?? "Не удалось загрузить профиль"
                return
            }

            persist(user: user)
            apply(user)
        } catch AuthError.serverError(let message) {
            errorMessage = message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

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
        name = "Name"
        username = "username"
        phoneNumber = "+7 (900) 900 90 90"
        avatarUrl = nil
        profileImage = nil
    }

    // MARK: - Private
    private func loadUserData() {
        guard let data = UserDefaults.standard.data(forKey: "userData") else { return }
        do {
            let user = try JSONDecoder().decode(User.self, from: data)
            name = user.name
            username = user.username ?? "username"
            phoneNumber = user.phoneNumber ?? phoneNumber
            avatarUrl = user.avatarUrl
            validateUsername()
        } catch {
        }
    }

    private func apply(_ user: User) {
        name = user.name
        username = user.username ?? username
        phoneNumber = user.phoneNumber ?? phoneNumber
        avatarUrl = user.avatarUrl
        validateUsername()
    }

    private func persist(user: User) {
        if let encoded = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(encoded, forKey: "userData")
        }
    }
}
