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
    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var scrollViewHeight: CGFloat = 0
    @State private var hasScrolledToBottom: Bool = false
    @State private var savedScrollPosition: UUID? = nil

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

            ZStack(alignment: .bottomTrailing) {
                ScrollViewReader { proxy in
                    ScrollView {
                        GeometryReader { geometry in
                            Color.clear
                                .preference(key: ScrollOffsetPreferenceKey.self, value: geometry.frame(in: .named("scroll")).minY)
                        }
                        .frame(height: 0)
                        
                        chatContent
                            .background(
                                GeometryReader { geometry in
                                    Color.clear
                                        .preference(key: ContentHeightPreferenceKey.self, value: geometry.size.height)
                                }
                            )
                    }
                    .coordinateSpace(name: "scroll")
                    .scrollDismissesKeyboard(.immediately)
                    .scrollIndicators(.hidden)
                    .simultaneousGesture(
                        TapGesture()
                            .onEnded { _ in
                                isInputFocused = false
                            }
                    )
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                        scrollOffset = value
                        updateScrollPosition(proxy: proxy)
                    }
                    .onPreferenceChange(ContentHeightPreferenceKey.self) { value in
                        contentHeight = value
                        updateScrollPosition(proxy: proxy)
                    }
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .preference(key: ScrollViewHeightPreferenceKey.self, value: geometry.size.height)
                        }
                    )
                    .onPreferenceChange(ScrollViewHeightPreferenceKey.self) { value in
                        scrollViewHeight = value
                        updateScrollPosition(proxy: proxy)
                    }
                    .onAppear {
                        // Restore scroll position or scroll to bottom immediately without animation
                        if let savedPosition = viewModel.getSavedScrollPosition(),
                           viewModel.messages.contains(where: { $0.id == savedPosition }) {
                            // Use immediate scroll without animation for saved position
                            proxy.scrollTo(savedPosition, anchor: .center)
                            savedScrollPosition = savedPosition
                        } else if let lastMessage = viewModel.messages.last, !hasScrolledToBottom {
                            // Scroll to bottom immediately without animation on first load
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            hasScrolledToBottom = true
                            viewModel.isAtBottom = true
                        }
                    }
                    .onChange(of: viewModel.messages.count) { oldCount, newCount in
                        if newCount > oldCount {
                            if let lastMessage = viewModel.messages.last {
                                if viewModel.isAtBottom {
                                    // Auto-scroll to bottom if user is already at bottom (with animation for new messages)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        withAnimation {
                                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                        }
                                    }
                                }
                            }
                        } else if oldCount == 0 && newCount > 0 {
                            // First load: scroll to bottom immediately without animation
                            if let lastMessage = viewModel.messages.last, !hasScrolledToBottom {
                                // Use a tiny delay to ensure layout is complete, but no animation
                                DispatchQueue.main.async {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                    hasScrolledToBottom = true
                                    viewModel.isAtBottom = true
                                }
                            }
                        }
                    }
                    .onChange(of: viewModel.isLoading) { isLoading in
                        // When loading finishes, scroll to bottom if we haven't scrolled yet
                        if !isLoading && !hasScrolledToBottom, let lastMessage = viewModel.messages.last {
                            DispatchQueue.main.async {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                hasScrolledToBottom = true
                                viewModel.isAtBottom = true
                            }
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        // New message indicator
                        if viewModel.unreadMessageCount > 0 && !viewModel.isAtBottom {
                            Button(action: {
                                if let lastMessage = viewModel.messages.last {
                                    withAnimation {
                                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                    }
                                    viewModel.isAtBottom = true
                                    viewModel.markAsRead()
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.down")
                                    Text("\(viewModel.unreadMessageCount) нов\(viewModel.unreadMessageCount == 1 ? "ое" : "ых")")
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color(hex: "#CADDAD"))
                                .cornerRadius(20)
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                            }
                            .padding(.trailing, 16)
                            .padding(.bottom, 100)
                        }
                    }
                }
            }

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
        .overlay {
            if viewModel.isLoading {
                ZStack {
                    Color.black.opacity(0.1)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Загрузка...")
                            .foregroundColor(.gray)
                            .font(.subheadline)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .onDisappear {
            // Stop typing when leaving chat
            typingTimer?.invalidate()
            viewModel.stopTyping()
            Task { @MainActor in
                viewModel.cleanup()
            }
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
                            Text((viewModel.recipientName.isEmpty ? "П" : viewModel.recipientName).prefix(1).uppercased())
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
                    Text(viewModel.recipientName.isEmpty ? "Пользователь" : viewModel.recipientName)
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
            if let error = viewModel.errorMessage {
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
                LazyVStack(spacing: 12) {
                    // Load older messages indicator
                    if viewModel.hasMoreMessages && !viewModel.isLoading {
                        HStack {
                            Spacer()
                            if viewModel.isLoadingOlderMessages {
                                ProgressView()
                                    .padding()
                            } else {
                                Button(action: {
                                    Task {
                                        await viewModel.loadOlderMessages()
                                    }
                                }) {
                                    Text("Загрузить старые сообщения")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .padding(.vertical, 8)
                                }
                            }
                            Spacer()
                        }
                        .onAppear {
                            // Auto-load when scrolling to top
                            Task {
                                await viewModel.loadOlderMessages()
                            }
                        }
                    }
                    
                    if viewModel.messages.isEmpty && !viewModel.isLoading {
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
                    } else if !viewModel.messages.isEmpty {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                onMediaTap: { media in
                                    selectedMedia = media
                                }
                            )
                            .id(message.id)
                            .onAppear {
                                // Save scroll position when message appears
                                if message.id == viewModel.messages.first?.id {
                                    viewModel.saveScrollPosition(messageId: message.id)
                                }
                            }
                        }
                    }
                    
                }
                .padding()
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
            
            // Typing indicator above input field (always visible)
            if viewModel.isTyping {
                HStack {
                    Text("\(viewModel.typingUserName) печатает...")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .italic()
                    Spacer()
                }
                .padding(.horizontal)
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

            ZStack(alignment: .topLeading) {
                // Placeholder text
                if viewModel.newMessageText.isEmpty {
                    Text("Введите сообщение...")
                        .foregroundColor(Color(uiColor: .placeholderText))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                
                // Multi-line text editor
                TextEditor(text: $viewModel.newMessageText)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($isInputFocused)
                    .frame(height: 36)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .onChange(of: viewModel.newMessageText) { oldValue, newValue in
                        // If text becomes empty, stop typing immediately
                        if newValue.isEmpty && !oldValue.isEmpty {
                            typingTimer?.invalidate()
                            viewModel.stopTyping()
                            return
                        }
                        
                        // If user starts typing (text was empty, now has content)
                        if !newValue.isEmpty && oldValue.isEmpty {
                            // Only start typing if keyboard is focused
                            if isInputFocused {
                                viewModel.startTyping()
                            }
                        }
                        
                        // If user continues typing, reset the timer
                        if !newValue.isEmpty {
                            typingTimer?.invalidate()
                            // Only send typing if keyboard is focused
                            if isInputFocused {
                                typingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                                    // Auto-stop typing after 3 seconds of inactivity
                                    if !viewModel.newMessageText.isEmpty {
                                        viewModel.stopTyping()
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: isInputFocused) { oldValue, newValue in
                        // When keyboard opens and there's text, start typing
                        if newValue && !viewModel.newMessageText.isEmpty {
                            viewModel.startTyping()
                        }
                        
                        // When keyboard closes, stop typing immediately
                        if !newValue && oldValue {
                            typingTimer?.invalidate()
                            viewModel.stopTyping()
                        }
                    }
            }
            .padding(8)
            .background(Color(uiColor: .systemGray6))
            .cornerRadius(20)

                Button(action: {
                    // Stop typing when sending message
                    typingTimer?.invalidate()
                    viewModel.stopTyping()
                    viewModel.sendMessage()
                    // Keep keyboard open after sending for continued typing
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

// MARK: - Preference Keys
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ScrollViewHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Helper Methods
extension ChatView {
    private func updateScrollPosition(proxy: ScrollViewProxy) {
        // Calculate if user is at bottom
        let threshold: CGFloat = 100 // Consider "at bottom" if within 100 points
        let isNearBottom = (contentHeight - scrollOffset - scrollViewHeight) < threshold
        
        if isNearBottom != viewModel.isAtBottom {
            viewModel.isAtBottom = isNearBottom
            if isNearBottom {
                viewModel.markAsRead()
            }
        }
        
        // Save scroll position periodically (when scrolling stops)
        if let firstVisibleMessage = viewModel.messages.first {
            viewModel.saveScrollPosition(messageId: firstVisibleMessage.id)
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
