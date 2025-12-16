import SwiftUI

// MARK: - Main View
struct ChatsView: View {
    @State private var viewModel = ChatsViewModel()
    @Environment(\.routingViewModel) private var routingViewModel

    // MARK: - Body View
    var body: some View {
        NavigationStack {
            ZStack {
                NavigationLink(
                    destination: EditProfileView(),
                    isActive: $viewModel.isEditProfileActive
                ) {
                    EmptyView()
                }
                
                if let user = viewModel.selectedUser {
                    NavigationLink(
                        destination: UserProfileView(user: user)
                            .environment(viewModel),
                        isActive: $viewModel.isUserProfileActive
                    ) {
                        EmptyView()
                    }
                }
                
                // Navigation handled via navigationDestination

                VStack(spacing: 0) {
                    header
                    ScrollView {
                        VStack(spacing: 0) {
                            if viewModel.isLoading {
                                ProgressView()
                                    .padding()
                            } else if viewModel.chats.isEmpty {
                                VStack {
                                    Spacer()
                                    Text("Нет чатов")
                                        .foregroundColor(.gray)
                                        .padding()
                                    Spacer()
                                }
                            } else {
                            chatsList
                            }
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    newChatButton
                }

                if viewModel.isSlideBarShowing {
                    SlideBarView(
                        isShowing: $viewModel.isSlideBarShowing,
                        currentUserName: viewModel.currentUserName,
                        username: viewModel.username,
                        avatarUrl: viewModel.avatarUrl,
                        activeScreen: .chats,
                        onNavigate: { screen in
                            if screen == .profile {
                                viewModel.isEditProfileActive = true
                            }
                        },
                        onLogout: {
                            viewModel.logout()
                            viewModel.isSlideBarShowing = false
                            routingViewModel.navigateToScreen(.login)
                        }
                    )
                }
            }
            .sheet(isPresented: $viewModel.isSearchUsersActive) {
                NavigationStack {
                    SearchUsersView { user in
                        viewModel.selectedUser = user
                        viewModel.isSearchUsersActive = false
                        viewModel.isUserProfileActive = true
                    }
                }
            }
            .navigationDestination(item: $viewModel.selectedChatInfo) { chatInfo in
                // Find ChatData for this conversation to get username and avatar
                let chatData = viewModel.chatDataList.first { $0.recipientId == chatInfo.userId }
                ChatView(
                    recipientId: chatInfo.userId,
                    recipientName: chatInfo.userName,
                    recipientUsername: chatData?.recipientUsername,
                    recipientAvatarUrl: chatData?.recipientAvatarUrl,
                    isRecipientOnline: chatInfo.isOnline,
                    conversationId: chatInfo.conversationId
                )
                .onDisappear {
                    // Clear selectedChatInfo when leaving chat to allow navigation again
                    viewModel.selectedChatInfo = nil
                }
            }
            .onAppear {
                // Reload conversations when view appears (e.g., when returning from chat)
                Task {
                    await viewModel.loadConversations()
                }
            }
        }
    }

    // MARK: - UI Components
    private var header: some View {
        HStack {
            Button(action: {
                viewModel.isSlideBarShowing.toggle()
            }) {
                Image(systemName: "line.3.horizontal")
                    .font(.title2)
                    .foregroundColor(.black)
            }

            Spacer()

            Text("PingMe")
                .font(.title2)
                .bold()

            Spacer()

            Button(action: {}) {
                Image(systemName: "bell")
                    .font(.title2)
                    .foregroundColor(.black)
            }
        }
        .padding()
        .background(Color(hex: "#CADDAD"))
    }

    // MARK: - Chats List
    private var chatsList: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.chatDataList) { chatData in
                VStack(spacing: 0) {
                    ChatRowView(
                        chat: chatData.chat,
                        recipientId: chatData.recipientId,
                        recipientName: chatData.recipientName,
                        recipientUsername: chatData.recipientUsername,
                        recipientAvatarUrl: chatData.recipientAvatarUrl,
                        isRecipientOnline: chatData.isRecipientOnline
                    )
                        .padding(.horizontal)
                        .padding(.vertical, 8)

                    Divider()
                        .background(Color(uiColor: .systemGray5))
                }
            }
        }
    }

    // MARK: - New Chat Button
    private var newChatButton: some View {
        Button(action: {
            viewModel.isSearchUsersActive = true
        }) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundColor(.black)
                .frame(width: 60, height: 60)
                .background(Color(hex: "#CADDAD"))
                .clipShape(Circle())
        }
        .padding()
    }
}

// MARK: - Story Component
struct StoryView: View {
    let story: Story
    var isCurrentUser: Bool = false

    var body: some View {
        VStack {
            ZStack {

                Circle()
                    .fill(Color(uiColor: .systemGray5))
                    .frame(width: 60, height: 60)

                if isCurrentUser {
                    Button(action: {}) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 19, height: 19)
                            .background(Color.black)
                            .clipShape(Circle())
                            .position(x: 50, y: 47)
                    }
                }
            }

            Text(story.username)
                .font(.caption)
                .lineLimit(1)
        }
    }
}

// MARK: - Chat Row Component
struct ChatRowView: View {
    let chat: Chat
    let recipientId: UUID?
    let recipientName: String
    let recipientUsername: String?
    let recipientAvatarUrl: String?
    let isRecipientOnline: Bool

    private var avatarUrlToUse: String? {
        recipientAvatarUrl ?? chat.avatarUrl
    }

    var body: some View {
        NavigationLink(destination: ChatView(
            recipientId: recipientId ?? UUID(),
            recipientName: recipientName,
            recipientUsername: recipientUsername,
            recipientAvatarUrl: recipientAvatarUrl,
            isRecipientOnline: isRecipientOnline,
            conversationId: chat.id
        )) {
            HStack(spacing: 12) {
                // Avatar
                ZStack(alignment: .bottomTrailing) {
                    if let avatarUrl = avatarUrlToUse, !avatarUrl.isEmpty {
                        CachedAsyncImage(urlString: avatarUrl) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                        } placeholder: {
                Circle()
                    .fill(Color(uiColor: .systemGray5))
                                .frame(width: 60, height: 60)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(0.8)
                                )
                        }
                    } else {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#CADDAD"), Color(hex: "#CADDAD").opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 60, height: 60)
                            .overlay(
                                Text(recipientName.prefix(1).uppercased())
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                    }
                    
                    // Online indicator
                    if isRecipientOnline && !chat.isGroup {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                            )
                    }
                }

                // Name and last message
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(recipientName)
                        .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(chat.lastMessageTime.formattedTime())
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }

                    Text(chat.lastMessage)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle()) // Make entire row tappable
            }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview
#Preview {
    ChatsView()
}
