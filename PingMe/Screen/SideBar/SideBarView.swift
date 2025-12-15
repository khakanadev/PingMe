import SwiftUI

// MARK: - Screen Enumeration
public enum ActiveScreen {
    case chats
    case suddenMeet
    case pingMe
    case settings
    case profile
}

// MARK: - Main View
struct SlideBarView: View {
    @Binding private var isShowing: Bool
    private let currentUserName: String
    private let username: String
    private let avatarUrl: String?
    @AppStorage("isDarkMode") private var isDarkMode = false
    private var activeScreen: ActiveScreen?
    private var onNavigate: ((ActiveScreen) -> Void)?
    private var onLogout: (() -> Void)?
    @State private var showWorkInProgressAlert = false

    // MARK: - Initialization
    init(
        isShowing: Binding<Bool>,
        currentUserName: String,
        username: String,
        avatarUrl: String? = nil,
        activeScreen: ActiveScreen? = nil,
        onNavigate: ((ActiveScreen) -> Void)? = nil,
        onLogout: (() -> Void)? = nil
    ) {
        self._isShowing = isShowing
        self.currentUserName = currentUserName
        self.username = username
        self.avatarUrl = avatarUrl
        self.activeScreen = activeScreen
        self.onNavigate = onNavigate
        self.onLogout = onLogout
    }

    // MARK: - Active Screen
    private func isActive(_ screen: ActiveScreen) -> Bool {
        return activeScreen == screen
    }

    // MARK: - Body View
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Color.black
                    .opacity(isShowing ? 0.2 : 0)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isShowing = false
                    }

                HStack(spacing: 0) {
                    VStack(spacing: 24) {
                        HStack(spacing: 16) {
                            if let avatarUrl = avatarUrl {
                                CachedAsyncImage(urlString: avatarUrl) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipShape(Circle())
                                } placeholder: {
                                    Circle()
                                        .fill(Color(hex: "#CADDAD"))
                                        .frame(width: 60, height: 60)
                                }
                            } else {
                                Circle()
                                    .fill(Color(hex: "#CADDAD"))
                                    .frame(width: 60, height: 60)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(currentUserName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("@\(username)")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                            }

                            Spacer()
                        }
                        .padding(.top, 100)

                        VStack(spacing: 12) {
                            Button(action: {
                                onNavigate?(.chats)
                                isShowing = false
                            }) {
                                HStack {
                                    Image(systemName: "bubble.left.and.bubble.right.fill")
                                    Text("Чаты")
                                        .font(.system(size: 16))
                                    Spacer()
                                }
                                .foregroundColor(.white)
                                .padding()
                                .background(isActive(.chats) ? Color(hex: "#CADDAD") : Color.black)
                                .cornerRadius(12)
                            }

                            Button(action: {
                                onNavigate?(.profile)
                                isShowing = false
                            }) {
                                HStack {
                                    Image(systemName: "person.fill")
                                    Text("Редактировать профиль")
                                        .font(.system(size: 16))
                                    Spacer()
                                }
                                .foregroundColor(.white)
                                .padding()
                                .background(
                                    isActive(.profile) ? Color(hex: "#CADDAD") : Color.black
                                )
                                .cornerRadius(12)
                            }

                            Button(action: {}) {
                                HStack {
                                    Image(systemName: "person.2.fill")
                                    Text("«Внезапная встреча»")
                                        .font(.system(size: 16))
                                    Spacer()
                                }
                                .foregroundColor(.white)
                                .padding()
                                .background(
                                    isActive(.suddenMeet) ? Color(hex: "#CADDAD") : Color.black
                                )
                                .cornerRadius(12)
                                .onTapGesture {
                                    showWorkInProgressAlert = true
                                }
                            }

                            Button(action: {}) {
                                HStack {
                                    Image(systemName: "location.circle.fill")
                                    Text("PingMe")
                                        .font(.system(size: 16))
                                    Spacer()
                                }
                                .foregroundColor(.white)
                                .padding()
                                .background(isActive(.pingMe) ? Color(hex: "#CADDAD") : Color.black)
                                .cornerRadius(12)
                                .onTapGesture {
                                    showWorkInProgressAlert = true
                                }
                            }

                            Button(action: {}) {
                                HStack {
                                    Image(systemName: "gearshape.fill")
                                    Text("Настройки")
                                        .font(.system(size: 16))
                                    Spacer()
                                }
                                .foregroundColor(.white)
                                .padding()
                                .background(
                                    isActive(.settings) ? Color(hex: "#CADDAD") : Color.black
                                )
                                .cornerRadius(12)
                                .onTapGesture {
                                    showWorkInProgressAlert = true
                                }
                            }
                        }

                        Spacer()

                        Divider()
                            .background(Color.gray)
                            .padding(.horizontal, -20)

                        VStack(spacing: 16) {
                            Toggle(isOn: $isDarkMode) {
                                HStack {
                                    Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                                    Text(isDarkMode ? "Темная тема" : "Светлая тема")
                                        .font(.system(size: 16))
                                }
                            }
                            .toggleStyle(SwitchToggleStyle(tint: Color(hex: "#CADDAD")))
                            .foregroundColor(.white)

                            Button(action: {
                                // Close WebSocket connection on logout
                                WebSocketService.shared.disconnect()
                                onLogout?()
                            }) {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                    Text("Выйти")
                                        .font(.system(size: 16))
                                }
                                .foregroundColor(.red)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(hex: "#444444"))
                                .cornerRadius(12)
                            }
                        }
                        .padding(.bottom, 32)
                    }
                    .padding(.horizontal, 20)
                    .frame(width: min(geometry.size.width * 0.8, 300))
                    .background(
                        Rectangle()
                            .fill(Color.black)
                            .padding(.leading, -50)
                    )

                    Spacer(minLength: 0)
                }
                .offset(x: isShowing ? 0 : -min(geometry.size.width * 0.8, 300) - 50)
            }
            .ignoresSafeArea()
            .alert("В разработке", isPresented: $showWorkInProgressAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Этот раздел пока в разработке.")
            }
        }
    }
}

// MARK: - Preview
#Preview {
    SlideBarView(
        isShowing: .constant(true),
        currentUserName: "Test User",
        username: "testuser"
    )
}
