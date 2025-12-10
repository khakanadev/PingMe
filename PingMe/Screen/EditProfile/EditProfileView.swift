import PhotosUI
import SwiftUI

// MARK: - EditProfileView
struct EditProfileView: View {
    @State private var viewModel = EditProfileViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showError = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.routingViewModel) private var routingViewModel

    // MARK: - Body
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: {
                        viewModel.isSlideBarShowing.toggle()
                    }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 40)

                // MARK: Profile Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Имя", text: Binding(
                            get: { viewModel.name },
                            set: { viewModel.updateName($0) }
                        ))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                        .textFieldStyle(.plain)

                        TextField("username", text: Binding(
                            get: { viewModel.username },
                            set: { viewModel.updateUsername($0) }
                        ))
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                        .textFieldStyle(.plain)
                        .autocapitalization(.none)
                    }
                    .padding(.leading, 25)
                    .padding(.top, 75)

                    Spacer()

                    ZStack(alignment: .bottomTrailing) {
                        if let image = viewModel.profileImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 150, height: 150)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.gray, lineWidth: 8)
                                )
                        } else if let avatarUrl = viewModel.avatarUrl {
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

                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.title2)
                                        .foregroundColor(.black)
                                )
                        }
                        .offset(x: 10, y: 10)
                        .onChange(of: selectedPhotoItem) { _, newItem in
                            guard let newItem else { return }
                            Task {
                                if let data = try? await newItem.loadTransferable(type: Data.self),
                                   let image = UIImage(data: data) {
                                    await MainActor.run {
                                        viewModel.updateProfileImage(image)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.horizontal)
                .padding(.bottom, 60)

                // MARK: Edit Fields
                VStack(spacing: 20) {
                    // MARK: Phone Number Field
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Номер телефона:")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.leading, 20)
                            .padding(.top, 10)

                        TextField(
                            "Введите номер",
                            text: Binding(
                                get: { viewModel.phoneNumber },
                                set: { viewModel.updatePhoneNumber($0) }
                            )
                        )
                        .keyboardType(.phonePad)
                        .font(.system(size: 19))
                        .foregroundColor(.black)
                        .padding(.leading, 20)
                        .padding(.vertical, 10)
                    }
                    .background(Color.white)
                    .cornerRadius(15)
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Имя:")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.leading, 20)
                            .padding(.top, 10)

                        TextField(
                            "Введите имя",
                            text: Binding(
                                get: { viewModel.name },
                                set: { viewModel.updateName($0) }
                            )
                        )
                        .font(.system(size: 19))
                        .foregroundColor(.black)
                        .padding(.leading, 20)
                        .padding(.vertical, 10)
                    }
                    .background(Color.white)
                    .cornerRadius(15)
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Username:")
                            .font(.system(size: 20, weight: .bold))
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .padding(.leading, 20)
                            .padding(.top, 10)

                        TextField(
                            "Введите username",
                            text: Binding(
                                get: { viewModel.username },
                                set: { newValue in
                                    viewModel.updateUsername(newValue)
                                }
                            )
                        )
                        .font(.system(size: 19))
                        .foregroundColor(.black)
                        .padding(.leading, 20)
                        .padding(.vertical, 10)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    }
                    .background(Color.white)
                    .cornerRadius(15)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(viewModel.isValidUsername ? Color.black : Color.red, lineWidth: 1)
                    )
                    .padding(.horizontal)
                }

                Spacer()

                Button(action: {
                    Task {
                        await viewModel.saveChanges()
                        if let error = viewModel.errorMessage {
                            showError = true
                        }
                    }
                }) {
                    Text("Сохранить изменения")
                        .foregroundColor(.black)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(hex: "#CADDAD"))
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
                .disabled(!viewModel.isValidUsername)
                .opacity(viewModel.isValidUsername ? 1.0 : 0.5)
                .padding(.bottom, 20)
            }
            .navigationBarBackButtonHidden(true)
            .alert("Ошибка", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "Что-то пошло не так")
            }

            // MARK: Sidebar
            SlideBarView(
                isShowing: $viewModel.isSlideBarShowing,
                currentUserName: viewModel.name,
                username: viewModel.username,
                avatarUrl: viewModel.avatarUrl,
                activeScreen: .profile,
                onNavigate: { screen in
                    if screen == .chats {
                        dismiss()
                    }
                },
                onLogout: {
                    viewModel.logout()
                    viewModel.isSlideBarShowing = false
                    routingViewModel.navigateToScreen(.login)
                }
            )

            if viewModel.isLoading || viewModel.isSaving {
                LoadingView()
            }
        }
    }
}

// MARK: - Preview
#Preview {
    EditProfileView()
}
