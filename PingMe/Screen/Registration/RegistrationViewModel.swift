import CoreFoundation
import Foundation
import Observation

// MARK: - View Model
@Observable
class RegistrationViewModel {
    private let authService = AuthService()
    var email: String
    var isValidEmail: Bool = true
    var password: String
    var confirmPassword: String
    var isValidPassword: Bool = true
    var isValidPasswordMatch: Bool = true
    var username: String = "@Kalashiq"
    var isValidUsername: Bool = true
    var showVerification: Bool = false
    var onBack: (() -> Void)?
    var isFromLogin: Bool = false
    var errorMessage: String?
    var usernameErrorMessage: String = ""
    var emailErrorMessage: String = ""
    var passwordErrorMessage: String = ""
    var confirmPasswordErrorMessage: String = ""

    // MARK: - Initialization
    init(
        email: String = "",
        password: String = "",
        confirmPassword: String = "",
        isFromLogin: Bool = false
    ) {
        self.email = email
        self.isValidEmail = true
        self.password = password
        self.confirmPassword = confirmPassword
        self.isValidPassword = true
        self.isFromLogin = isFromLogin

    }

    // MARK: - Validation Methods
    func validateUsername() {
        // Check if username contains any non-ASCII letters (Russian, etc.)
        let hasNonEnglish = username.contains { char in
            char.isLetter && !char.isASCII
        }
        
        // Only allow English letters (A-Z, a-z), numbers (0-9), underscore, and @ at the start
        let usernameRegex = "^@[A-Za-z0-9_]{5,}$"
        let usernamePredicate = NSPredicate(format: "SELF MATCHES %@", usernameRegex)
        
        isValidUsername = !hasNonEnglish && usernamePredicate.evaluate(with: username)
        usernameErrorMessage = isValidUsername ? "" : "Username должен начинаться с '@' и содержать минимум 6 символов (только английские буквы, цифры и подчеркивание)".localized
    }
    func validateEmail() {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        isValidEmail = emailPredicate.evaluate(with: email)
        emailErrorMessage = isValidEmail ? "" : "Invalid email format".localized
    }
    func validatePassword() {
        isValidPassword = password.count >= 8
        passwordErrorMessage = isValidPassword ? "" : "The password must contain at least 8 characters.".localized
    }
    func validatePasswordMatch() {
        isValidPasswordMatch =
            !password.isEmpty && !confirmPassword.isEmpty && password == confirmPassword
        confirmPasswordErrorMessage = isValidPasswordMatch ? "" : "Passwords must match".localized
    }
    func isValidForm() -> Bool {
        isValidEmail && isValidPassword && isValidPasswordMatch && isValidUsername && !email.isEmpty
            && !password.isEmpty && !confirmPassword.isEmpty && !username.isEmpty
    }

    // MARK: - Authentication Methods
    @MainActor
    func register() async {
        do {
            let response = try await authService.register(
                email: email,
                password: password,
                name: username.replacingOccurrences(of: "@", with: "")
            )

            if !response.success {
                errorMessage = response.error ?? "Registration failed".localized
                return
            }

            print("Registration successful, setting isFromLogin to false")
            isFromLogin = false
            showVerification = true

        } catch {
            print("Registration error: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func verifyRegistration(token: String) async -> VerifyResponseData? {
        do {
            isFromLogin = false
            let response = try await authService.verifyRegistration(
                email: email,
                password: password,
                token: token
            )

            if !response.success {
                errorMessage = response.error ?? "Verification failed".localized
                return nil
            }

            return response.data

        } catch {
            print("Verification error: \(error)")
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
