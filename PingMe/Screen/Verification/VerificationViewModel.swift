import CoreFoundation
import Foundation
import Observation

// MARK: - View Model
@Observable
class VerificationViewModel {
    private let authService = AuthService()
    var verificationCode: [String] = Array(repeating: "", count: 6)
    var timeRemaining = 180
    var timer: Timer?
    var canResendCode = false
    var email: String
    var onBack: () -> Void = {}
    private let password: String
    var username: String = ""
    var isFromLogin: Bool
    var errorMessage: String?

    // MARK: - Initialization
    init(email: String, password: String, isFromLogin: Bool, username: String = "") {
        self.email = email
        self.password = password
        self.isFromLogin = isFromLogin
        self.username = username
    }

    // MARK: - Timer Management
    func startTimer() {
        canResendCode = false
        timeRemaining = 180
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
            } else {
                self.canResendCode = true
                self.timer?.invalidate()
            }
        }
    }

    var formattedTime: String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Input Handling
    func handleCodeInput(at index: Int, newValue: String) -> Int? {
        // Handle single character input only (paste is handled separately)
        if !newValue.isEmpty && !newValue.allSatisfy({ $0.isNumber }) {
            verificationCode[index] = ""
            return nil
        }
        
        verificationCode[index] = newValue.isEmpty ? "" : String(newValue.prefix(1))

        if !newValue.isEmpty && index < 5 {
            return index + 1
        }

        if newValue.isEmpty && index > 0 {
            return index - 1
        }

        return nil
    }
    
    // MARK: - Paste Handling
    @MainActor
    func pasteCode(_ code: String) {
        // Extract only digits and limit to 6
        let digits = code.filter { $0.isNumber }.prefix(6)
        let digitsString = String(digits)
        
        // Create new array with all values at once to trigger single SwiftUI update
        var newCodeArray = Array(repeating: "", count: 6)
        for (index, char) in digitsString.enumerated() {
            if index < 6 {
                newCodeArray[index] = String(char)
            }
        }
        
        // Update all fields at once - this triggers a single SwiftUI update
        verificationCode = newCodeArray
    }

    // MARK: - Lifecycle Methods
    func onDisappear() {
        timer?.invalidate()
    }

    // MARK: - Authentication Methods
    @MainActor
    func verifyCode() async -> VerifyResponseData? {
        let code = verificationCode.joined()

        if code.count != 6 {
            errorMessage = "The code must consist of 6 digits.".localized
            return nil
        }

        do {
            let response =
                try await isFromLogin
                ? authService.verifyLogin(email: email, password: password, token: code)
                : authService.verifyRegistration(email: email, password: password, token: code)

            if !response.success {
                errorMessage = "Invalid confirmation code".localized
                clearVerificationCode()
                return nil
            }

            guard let userData = response.data else {
                errorMessage = "Successful response without user data".localized
                return nil
            }

            return userData

        } catch {
            errorMessage = "Invalid confirmation code".localized
            clearVerificationCode()
            return nil
        }
    }

    // MARK: - Data Management
    func saveUserData(_ userData: VerifyResponseData) {
        UserDefaults.standard.set(userData.tokens.access.token, forKey: "accessToken")
        UserDefaults.standard.set(userData.tokens.refresh.token, forKey: "refreshToken")
        UserDefaults.standard.set(
            userData.tokens.access.expiresAt.timeIntervalSince1970, forKey: "accessTokenExpiration")
        UserDefaults.standard.set(
            userData.tokens.refresh.expiresAt.timeIntervalSince1970,
            forKey: "refreshTokenExpiration")

        if let encodedUser = try? JSONEncoder().encode(userData.user) {
            UserDefaults.standard.set(encodedUser, forKey: "userData")
        }

        UserDefaults.standard.synchronize()
    }

    // MARK: - Code Resend
    func resendCode() async {
        if canResendCode {
            do {
                let response =
                    try await isFromLogin
                    ? authService.login(email: email, password: password)
                    : authService.register(email: email, password: password, name: username)

                if response.success {
                    await MainActor.run {
                        startTimer()
                    }
                } else {
                    errorMessage = response.error ?? "Failed to resend code".localized
                }
            } catch {
                errorMessage = "Failed to resend code".localized
            }
        }
    }

    // MARK: - Helper Methods
    private func clearVerificationCode() {
        verificationCode = Array(repeating: "", count: 6)
    }
}
