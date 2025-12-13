import Foundation
import Observation

@Observable
class SearchUsersViewModel {
    private let profileService = ProfileService()
    
    var searchQuery: String = ""
    var searchResults: [UserBrief] = []
    var isLoading: Bool = false
    var errorMessage: String?
    
    func searchUsers() async {
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let response = try await profileService.searchUsers(query: searchQuery)
            if response.success, let users = response.data {
                await MainActor.run {
                    searchResults = users
                }
            } else {
                await MainActor.run {
                    errorMessage = response.error ?? "Не удалось выполнить поиск"
                    searchResults = []
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                searchResults = []
            }
        }
    }
}
