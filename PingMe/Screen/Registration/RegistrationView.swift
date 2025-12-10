import SwiftUI

// MARK: - Main View
struct RegistrationView: View {
    @State private var viewModel = RegistrationViewModel(
        email: "Kalashiq.org@gmail.com",
        password: "Password#123",
        confirmPassword: "Password#123",
        isFromLogin: false
    )

    @Environment(\.dismiss) private var dismiss
    @Binding var contentOpacity: Double
    @Binding var backgroundHeight: CGFloat
    @Binding var backgroundWidth: CGFloat
    @Binding var isAnimating: Bool
    @State private var isLoading = false

    var body: some View {
        ZStack {
            Color(hex: "#CADDAD").ignoresSafeArea()

            if viewModel.showVerification {
                VerificationView(
                    email: viewModel.email,
                    password: viewModel.password,
                    isFromLogin: false,
                    contentOpacity: .constant(0),
                    backgroundHeight: .constant(UIScreen.main.bounds.height),
                    backgroundWidth: .constant(UIScreen.main.bounds.width),
                    isAnimating: .constant(true),
                    onBack: {
                        withAnimation(.spring()) {
                            viewModel.showVerification = false
                        }
                    },
                    username: viewModel.username.replacingOccurrences(of: "@", with: "")
                )
                .transition(.move(edge: .trailing))
            } else {
                VStack(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Registration")
                            .font(.custom("Inter", size: 40))
                            .fontWeight(.medium)
                            .lineSpacing(62.93)
                            .padding(.leading, 21)

                        VStack(alignment: .center, spacing: 14) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Your name:")
                                    .font(.custom("Inter", size: 21))
                                    .fontWeight(.regular)
                                    .foregroundColor(Color(hex: "#525252"))
                                    .padding(.horizontal, 8)
                                    .frame(width: 120, height: 23)
                                    .background(Color(hex: "#CADDAD"))
                                    .zIndex(1)
                                    .offset(x: 16, y: 10)

                                TextField("", text: Binding(
                                    get: { viewModel.username },
                                    set: { newValue in
                                        viewModel.username = newValue
                                        viewModel.validateUsername()
                                    }
                                ))
                                    .padding()
                                    .frame(width: 322, height: 60)
                                    .background(Color(hex: "#CADDAD"))
                                    .cornerRadius(8)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8).stroke(
                                            viewModel.isValidUsername ? Color.black : Color.red,
                                            lineWidth: 1))
                                if !viewModel.usernameErrorMessage.isEmpty {
                                    Text(viewModel.usernameErrorMessage)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .padding(.leading, 16)
                                        .padding(.top, 4)
                                }
                            }

                            VStack(alignment: .leading, spacing: 0) {
                                Text("E-mail:")
                                    .font(.custom("Inter", size: 21))
                                    .fontWeight(.regular)
                                    .foregroundColor(Color(hex: "#525252"))
                                    .padding(.horizontal, 8)
                                    .frame(width: 95, height: 23)
                                    .background(Color(hex: "#CADDAD"))
                                    .zIndex(1)
                                    .offset(x: 16, y: 10)

                                TextField("", text: $viewModel.email)
                                    .onChange(of: viewModel.email) { _, _ in
                                        viewModel.validateEmail()
                                    }
                                    .padding()
                                    .frame(width: 322, height: 60)
                                    .background(Color(hex: "#CADDAD"))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8).stroke(
                                            viewModel.isValidEmail ? Color.black : Color.red,
                                            lineWidth: 1))
                                if !viewModel.emailErrorMessage.isEmpty {
                                    Text(viewModel.emailErrorMessage)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .padding(.leading, 16)
                                        .padding(.top, 4)
                                }
                            }

                            VStack(alignment: .leading, spacing: 0) {
                                Text("Password")
                                    .font(.custom("Inter", size: 21))
                                    .fontWeight(.regular)
                                    .foregroundColor(Color(hex: "#525252"))
                                    .padding(.horizontal, 8)
                                    .frame(width: 103, height: 23)
                                    .background(Color(hex: "#CADDAD"))
                                    .zIndex(1)
                                    .offset(x: 16, y: 10)

                                SecureField("", text: $viewModel.password)
                                    .onChange(of: viewModel.password) { _, _ in
                                        viewModel.validatePassword()
                                        viewModel.validatePasswordMatch()
                                    }
                                    .padding()
                                    .frame(width: 322, height: 60)
                                    .background(Color(hex: "#CADDAD"))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8).stroke(
                                            viewModel.isValidPassword ? Color.black : Color.red,
                                            lineWidth: 1))
                                if !viewModel.passwordErrorMessage.isEmpty {
                                    Text(viewModel.passwordErrorMessage)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .padding(.leading, 16)
                                        .padding(.top, 4)
                                }
                            }

                            VStack(alignment: .leading, spacing: 0) {
                                Text("Confirmation")
                                    .font(.custom("Inter", size: 21))
                                    .fontWeight(.regular)
                                    .foregroundColor(Color(hex: "#525252"))
                                    .padding(.horizontal, 8)
                                    .frame(width: 190, height: 23)
                                    .background(Color(hex: "#CADDAD"))
                                    .zIndex(1)
                                    .offset(x: 16, y: 10)

                                SecureField("", text: $viewModel.confirmPassword)
                                    .onChange(of: viewModel.confirmPassword) { _, _ in
                                        viewModel.validatePassword()
                                        viewModel.validatePasswordMatch()
                                    }
                                    .padding()
                                    .frame(width: 322, height: 60)
                                    .background(Color(hex: "#CADDAD"))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8).stroke(
                                            viewModel.isValidPasswordMatch
                                                ? Color.black : Color.red, lineWidth: 1))
                                if !viewModel.confirmPasswordErrorMessage.isEmpty {
                                    Text(viewModel.confirmPasswordErrorMessage)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .padding(.leading, 16)
                                        .padding(.top, 4)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 28)

                        HStack {
                            Button(action: {
                                if viewModel.isValidForm() {
                                    Task {
                                        isLoading = true
                                        await viewModel.register()
                                        isLoading = false
                                    }
                                }
                            }) {
                                Image(systemName: "arrow.right")
                                    .font(.title)
                                    .foregroundColor(.white)
                                    .frame(width: 60, height: 60)
                                    .background(Color.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .padding(.leading, 288)
                            }
                            .padding(.top, 26)
                            .padding(.bottom, 26)
                        }

                        Button(action: {
                            withAnimation(.easeInOut(duration: 1.1)) {
                                backgroundHeight = 745
                                backgroundWidth = 400
                                contentOpacity = 1
                            }

                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                                isAnimating = false
                            }
                        }) {
                            Text("Already have an account? Enter")
                                .foregroundColor(Color(hex: "#525252"))
                                .frame(width: 261, height: 52)
                                .background(Color.white)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8).stroke(
                                        Color.white, lineWidth: 1)
                                )
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding(.top, 90)
                    .padding()
                }
                .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height, alignment: .top)
            }

            if isLoading {
                LoadingView()
            }
        }
        .animation(.spring(), value: viewModel.showVerification)
    }
}

// MARK: - Preview
#Preview {
    RegistrationView(
        contentOpacity: .constant(0),
        backgroundHeight: .constant(UIScreen.main.bounds.height),
        backgroundWidth: .constant(UIScreen.main.bounds.width),
        isAnimating: .constant(true)
    )
}
