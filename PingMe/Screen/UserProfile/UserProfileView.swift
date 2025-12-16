import SwiftUI

struct UserProfileView: View {
    let user: UserBrief
    @Environment(\.dismiss) private var dismiss
    var chatsViewModel: ChatsViewModel? = nil
    var onOpenChat: ((UUID, String, Bool) -> Void)? = nil
    var showWriteButton: Bool = true
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Back Button
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "arrow.left")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 40)
                
                // Profile Header
                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(user.name)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if let username = user.username {
                            Text("@\(username)")
                                .font(.system(size: 20))
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 25)
                    .padding(.top, 75)
                    
                    Spacer(minLength: 0)
                    
                    ZStack(alignment: .bottomTrailing) {
                        if let avatarUrl = user.avatarUrl {
                            CachedAsyncImage(urlString: avatarUrl) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 150, height: 150)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color.gray, lineWidth: 8)
                                    )
                            } placeholder: {
                                Circle()
                                    .fill(Color(hex: "#CADDAD"))
                                    .frame(width: 150, height: 150)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.gray, lineWidth: 8)
                                    )
                            }
                        } else {
                            Circle()
                                .fill(Color(hex: "#CADDAD"))
                                .frame(width: 150, height: 150)
                                .overlay(
                                    Circle()
                                        .stroke(Color.gray, lineWidth: 8)
                                )
                        }
                        
                        if user.isOnline {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle()
                                        .stroke(Color.black, lineWidth: 2)
                                )
                                .offset(x: 10, y: 10)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.horizontal)
                .padding(.bottom, 60)
                
                // User Info
                VStack(spacing: 20) {
                    if let username = user.username {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Username:")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.leading, 20)
                                .padding(.top, 10)
                            
                            HStack(spacing: 0) {
                                Text("@\(username)")
                                    .font(.system(size: 19))
                                    .foregroundColor(.black)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.leading, 20)
                            .padding(.trailing, 20)
                            .padding(.vertical, 10)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white)
                        .cornerRadius(15)
                        .padding(.horizontal)
                    }
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Статус:")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.leading, 20)
                            .padding(.top, 10)
                        
                        HStack {
                            Text(user.isOnline ? "В сети" : "Не в сети")
                                .font(.system(size: 19))
                                .foregroundColor(.black)
                            
                            if user.isOnline {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 10, height: 10)
                            }
                            
                            Spacer()
                        }
                        .padding(.leading, 20)
                        .padding(.vertical, 10)
                    }
                    .background(Color.white)
                    .cornerRadius(15)
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // Action Buttons
                if showWriteButton {
                    HStack(spacing: 12) {
                        Button(action: {
                            if let onOpenChat = onOpenChat {
                                onOpenChat(user.id, user.name, user.isOnline)
                                dismiss()
                            } else if let chatsViewModel = chatsViewModel {
                                chatsViewModel.openChat(
                                    with: user.id,
                                    userName: user.name,
                                    isOnline: user.isOnline
                                )
                                dismiss()
                            }
                        }) {
                            Text("Написать")
                                .foregroundColor(.black)
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color(hex: "#CADDAD"))
                                .cornerRadius(12)
                        }
                        
                        Button(action: {
                            shareContact()
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                                .foregroundColor(.white)
                                .frame(width: 60)
                                .frame(height: 50)
                                .background(Color(hex: "#444444"))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                } else {
                    Button(action: {
                        shareContact()
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                            Text("Поделиться контактом")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(hex: "#444444"))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
    
    private func shareContact() {
        var shareText = user.name
        if let username = user.username {
            shareText += "\n@\(username)"
        }
        
        let activityVC = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }
}
