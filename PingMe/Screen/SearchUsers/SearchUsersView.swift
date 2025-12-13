import SwiftUI

struct SearchUsersView: View {
    @State private var viewModel = SearchUsersViewModel()
    @Environment(\.dismiss) private var dismiss
    var onUserSelected: ((UserBrief) -> Void)?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#CADDAD").ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search Bar
                    HStack {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "arrow.left")
                                .font(.title2)
                                .foregroundColor(.black)
                        }
                        
                        TextField("Поиск", text: $viewModel.searchQuery)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white)
                            .cornerRadius(12)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .onSubmit {
                                Task {
                                    await viewModel.searchUsers()
                                }
                            }
                            .onChange(of: viewModel.searchQuery) { _, newValue in
                                if newValue.isEmpty {
                                    viewModel.searchResults = []
                                } else {
                                    Task {
                                        // Debounce search
                                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                                        if viewModel.searchQuery == newValue {
                                            await viewModel.searchUsers()
                                        }
                                    }
                                }
                            }
                    }
                    .padding()
                    .background(Color(hex: "#CADDAD"))
                    
                    // Results
                    if viewModel.isLoading {
                        Spacer()
                        ProgressView()
                        Spacer()
                    } else if viewModel.searchResults.isEmpty && !viewModel.searchQuery.isEmpty {
                        Spacer()
                        Text("Ничего не найдено")
                            .foregroundColor(.gray)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(viewModel.searchResults) { user in
                                    Button(action: {
                                        onUserSelected?(user)
                                    }) {
                                        HStack(spacing: 12) {
                                            if let avatarUrl = user.avatarUrl {
                                                CachedAsyncImage(urlString: avatarUrl) { image in
                                                    image
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(width: 50, height: 50)
                                                        .clipShape(Circle())
                                                } placeholder: {
                                                    Circle()
                                                        .fill(Color(hex: "#CADDAD"))
                                                        .frame(width: 50, height: 50)
                                                }
                                            } else {
                                                Circle()
                                                    .fill(Color(hex: "#CADDAD"))
                                                    .frame(width: 50, height: 50)
                                            }
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(user.name)
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(.black)
                                                
                                                if let username = user.username {
                                                    Text("@\(username)")
                                                        .font(.system(size: 14))
                                                        .foregroundColor(.gray)
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            if user.isOnline {
                                                Circle()
                                                    .fill(Color.green)
                                                    .frame(width: 10, height: 10)
                                            }
                                        }
                                        .padding()
                                        .background(Color.white)
                                    }
                                    
                                    Divider()
                                        .background(Color(uiColor: .systemGray5))
                                }
                            }
                        }
                    }
                }
            }
            .navigationBarBackButtonHidden(true)
        }
    }
}
