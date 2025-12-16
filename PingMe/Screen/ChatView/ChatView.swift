import SwiftUI
import PhotosUI

// MARK: - Main View
// swiftlint:disable type_body_length
struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInputFocused: Bool
    @State private var typingTimer: Timer?
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedMedia: MessageMedia? = nil
    @State private var showUserProfile: Bool = false
    @State private var userProfileData: UserBrief? = nil
    @State private var isLoadingProfile: Bool = false

    // MARK: - Initialization
    init(recipientId: UUID, recipientName: String, recipientUsername: String? = nil, recipientAvatarUrl: String? = nil, isRecipientOnline: Bool = true, conversationId: UUID? = nil) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(
            recipientId: recipientId,
            recipientName: recipientName,
            recipientUsername: recipientUsername,
            recipientAvatarUrl: recipientAvatarUrl,
            isRecipientOnline: isRecipientOnline,
            conversationId: conversationId
        ))
    }

    // MARK: - Body View
    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                chatContent
            }
            .scrollDismissesKeyboard(.immediately)
            .scrollIndicators(.hidden)
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        isInputFocused = false
                    }
            )

            messageInputField
        }
        .background(
            LinearGradient(
                colors: [Color(hex: "#CADDAD").opacity(0.8), .white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationBarHidden(true)
        .onDisappear {
            Task { @MainActor in
                viewModel.cleanup()
            }
            typingTimer?.invalidate()
        }
        .alert("Ошибка", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .fullScreenCover(item: $selectedMedia) { media in
            MediaViewerView(mediaId: media.id)
        }
        .sheet(isPresented: $showUserProfile) {
            if let user = userProfileData {
                NavigationStack {
                    UserProfileView(
                        user: user,
                        chatsViewModel: nil,
                        onOpenChat: { userId, userName, isOnline in
                            // Handle opening chat from profile - already in chat, so just dismiss
                            dismiss()
                        },
                        showWriteButton: false
                    )
                }
            } else {
                // Show loading state
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                }
            }
        }
    }

    // MARK: - UI Components
    private var header: some View {
        HStack(spacing: 16) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.title2)
            }

            // Avatar - clickable
            Button(action: {
                loadUserProfile()
            }) {
                if let avatarUrl = viewModel.recipientAvatarUrl, !avatarUrl.isEmpty {
                    CachedAsyncImage(urlString: avatarUrl) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } placeholder: {
                Circle()
                    .fill(Color(uiColor: .systemGray5))
                    .frame(width: 40, height: 40)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.6)
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
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(viewModel.recipientName.prefix(1).uppercased())
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        )
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Name and status - clickable
            Button(action: {
                loadUserProfile()
            }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.recipientName)
                        .font(.system(size: 16, weight: .semibold))

                    HStack(spacing: 4) {
                        Circle()
                            .fill(viewModel.isRecipientOnline ? .green : .gray)
                            .frame(width: 8, height: 8)

                        Text(viewModel.isRecipientOnline ? "online" : "offline")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            VStack(spacing: 2) {
                Image(systemName: "bell")
                Text("PingMe")
                    .font(.caption)
            }

            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .font(.title2)
            }
        }
        .padding()
        .foregroundColor(.black)
        .background(Color(hex: "#CADDAD"))
    }

    // MARK: - Chat Content
    private var chatContent: some View {
        Group {
            if viewModel.isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                    Text("Загрузка...")
                        .foregroundColor(.gray)
                        .padding(.top)
                    Spacer()
                }
            } else if let error = viewModel.errorMessage {
                VStack {
                    Spacer()
                    Text("Ошибка")
                        .font(.headline)
                        .foregroundColor(.red)
                    Text(error)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
        LazyVStack(spacing: 12) {
                        if viewModel.messages.isEmpty {
                            VStack {
                                Spacer()
                                Text("Нет сообщений")
                                    .foregroundColor(.gray)
                                Text("Начните общение, отправив сообщение")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.top, 4)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
            ForEach(viewModel.messages) { message in
                MessageBubble(
                    message: message,
                    onMediaTap: { media in
                        selectedMedia = media
                    }
                )
                .id(message.id)
            }
                        }
                        
                        if viewModel.isTyping {
                            HStack {
                                Text("\(viewModel.typingUserName) печатает...")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .italic()
                                Spacer()
                            }
                            .padding(.horizontal)
            }
        }
        .padding()
                    .onChange(of: viewModel.messages.count) { oldCount in
                        let newCount = viewModel.messages.count
                        if newCount > oldCount, let lastMessage = viewModel.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Message Input
    private var messageInputField: some View {
        VStack(spacing: 8) {
            if !viewModel.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.attachments, id: \.id) { item in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: item.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipped()
                                    .cornerRadius(12)
                                
                                Button(action: {
                                    viewModel.removeAttachment(id: item.id)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white)
                                        .background(Color.black.opacity(0.6))
                                        .clipShape(Circle())
                                }
                                .offset(x: 6, y: -6)
                                
                                if case .uploading = item.state {
                                    ProgressView()
                                        .tint(.white)
                                        .frame(width: 64, height: 64)
                                        .background(Color.black.opacity(0.3))
                                        .cornerRadius(12)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                }
                .padding(.top, 12)
                .padding(.bottom, 4)
            }
            
        HStack(spacing: 12) {
                PhotosPicker(selection: $selectedItems, matching: .images) {
                Image(systemName: "paperclip")
                    .font(.title2)
            }
                .onChange(of: selectedItems) { _, items in
                    Task {
                        for item in items {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                viewModel.addAttachment(image)
                            }
                        }
                        selectedItems.removeAll()
                    }
            }

            TextField("Введите сообщение...", text: $viewModel.newMessageText)
                .padding(8)
                .background(Color(uiColor: .systemGray6))
                .cornerRadius(20)
                .focused($isInputFocused)
                    .onChange(of: viewModel.newMessageText) { oldValue in
                        let newValue = viewModel.newMessageText
                        if !newValue.isEmpty && oldValue.isEmpty {
                            viewModel.startTyping()
                        }
                        
                        // Reset typing timer
                        typingTimer?.invalidate()
                        typingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                            if !viewModel.newMessageText.isEmpty {
                                viewModel.stopTyping()
                            }
                        }
                    }
                .onSubmit {
                        viewModel.stopTyping()
                    viewModel.sendMessage()
                }

                Button(action: {
                    viewModel.sendMessage()
                    isInputFocused = false
                }) {
                    Image(systemName: "paperplane.fill")
                        .font(.title2)
                        .foregroundColor(viewModel.isSending ? Color.gray : Color(hex: "#CADDAD"))
            }
            .disabled(viewModel.isSending)
        }
        .padding()
        .foregroundColor(.black)
        }
    }
    
    // MARK: - User Profile Loading
    private func loadUserProfile() {
        guard !isLoadingProfile else { return }
        
        isLoadingProfile = true
        showUserProfile = true // Show sheet immediately with loading state
        
        Task {
            do {
                let profileService = ProfileService()
                let response = try await profileService.getUserById(viewModel.recipientId)
                
                await MainActor.run {
                    if let user = response.data {
                        userProfileData = user
                    } else {
                        // If no data, create a basic UserBrief from available info
                        userProfileData = UserBrief(
                            id: viewModel.recipientId,
                            name: viewModel.recipientName,
                            username: viewModel.recipientUsername,
                            isOnline: viewModel.isRecipientOnline,
                            lastSeen: nil,
                            avatarUrl: viewModel.recipientAvatarUrl
                        )
                    }
                    isLoadingProfile = false
                }
            } catch {
                // On error, create a basic UserBrief from available info
                await MainActor.run {
                    userProfileData = UserBrief(
                        id: viewModel.recipientId,
                        name: viewModel.recipientName,
                        username: viewModel.recipientUsername,
                        isOnline: viewModel.isRecipientOnline,
                        lastSeen: nil,
                        avatarUrl: viewModel.recipientAvatarUrl
                    )
                    isLoadingProfile = false
                }
            }
        }
    }
}

// MARK: - Message Bubble Component
struct MessageBubble: View {
    let message: MessageDisplay
    let onMediaTap: (MessageMedia) -> Void

    var body: some View {
        HStack {
            if message.isFromCurrentUser { Spacer() }

            VStack(alignment: message.isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                if !message.isFromCurrentUser {
                    Text(message.senderName)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 4)
                }
                
                VStack(alignment: message.isFromCurrentUser ? .trailing : .leading, spacing: 8) {
                    // Check if content is empty (only whitespace)
                    let trimmedContent = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    let hasText = !trimmedContent.isEmpty
                    
                    if !message.media.isEmpty {
                        ForEach(message.media) { media in
                            // Use mediaId to load through API endpoint (authenticated)
                            ZStack(alignment: .bottomTrailing) {
                                CachedAsyncImage(urlString: nil, mediaId: media.id) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 200, height: 200)
                                        .clipped()
                                        .cornerRadius(16)
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(uiColor: .systemGray5))
                                        .frame(width: 200, height: 200)
                                        .overlay(ProgressView())
                                }
                                
                                // Show timestamp overlay on media if no text
                                if !hasText {
                                    HStack(spacing: 4) {
                                        Text(message.timestamp.formattedTime())
                                            .font(.caption2)
                                            .foregroundColor(.white)
                                        
                                        if message.isEdited {
                                            Image(systemName: "pencil")
                                                .font(.caption2)
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .padding(8)
                                    .background(Color.black.opacity(0.5))
                                    .cornerRadius(8)
                                    .padding(8)
                                }
                            }
                            .onTapGesture {
                                onMediaTap(media)
                            }
                        }
                    }
                    
                    // Only show text bubble if there's actual text
                    if hasText {
                        Text(message.isDeleted ? "Сообщение удалено" : message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .padding(.bottom, 16)
                    .overlay(
                                HStack(spacing: 4) {
                        Text(message.timestamp.formattedTime())
                            .font(.caption2)
                            .foregroundColor(.gray)
                                    
                                    if message.isEdited {
                                        Image(systemName: "pencil")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                }
                            .padding([.trailing, .bottom], 8),
                        alignment: .bottomTrailing
                    )
                    .background(message.isFromCurrentUser ? Color(uiColor: .systemGray5) : .white)
                    .cornerRadius(20)
                            .opacity(message.isDeleted ? 0.6 : 1.0)
                    }
                }
            }

            if !message.isFromCurrentUser { Spacer() }
        }
    }
}

// MARK: - Preview
#Preview {
    ChatView(
        recipientId: UUID(),
        recipientName: "Тестовый пользователь",
        recipientUsername: "testuser",
        recipientAvatarUrl: nil,
        isRecipientOnline: true
    )
}
