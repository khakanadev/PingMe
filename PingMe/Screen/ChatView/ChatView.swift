import SwiftUI

// MARK: - Main View
struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInputFocused: Bool
    @State private var typingTimer: Timer?

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
    }

    // MARK: - UI Components
    private var header: some View {
        HStack(spacing: 16) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.title2)
            }

            // Avatar
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
                                MessageBubble(message: message)
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
        HStack(spacing: 12) {
            Button(action: {}) {
                Image(systemName: "paperclip")
                    .font(.title2)
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

            if viewModel.newMessageText.isEmpty {
                Button(action: {}) {
                    Image(systemName: "mic")
                        .font(.title2)
                }

                Button(action: {}) {
                    Image(systemName: "video")
                        .font(.title2)
                }
            } else {
                Button(action: {
                    viewModel.sendMessage()
                    isInputFocused = false
                }) {
                    Image(systemName: "paperplane.fill")
                        .font(.title2)
                        .foregroundColor(Color(hex: "#CADDAD"))
                }
            }
        }
        .padding()
        .foregroundColor(.black)
    }
}

// MARK: - Message Bubble Component
struct MessageBubble: View {
    let message: MessageDisplay

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
