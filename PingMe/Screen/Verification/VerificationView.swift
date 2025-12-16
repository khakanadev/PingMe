import SwiftUI

// MARK: - Main View
struct VerificationView: View {
    @State private var viewModel: VerificationViewModel
    @Environment(\.dismiss) private var dismiss
    @Binding var contentOpacity: Double
    @Binding var backgroundHeight: CGFloat
    @Binding var backgroundWidth: CGFloat
    @Binding var isAnimating: Bool
    @FocusState private var focusedField: Int?
    @State private var showError = false
    @State private var errorMessage = ""
    @Environment(\.routingViewModel) private var routingViewModel
    private let password: String
    @State private var isLoading = false
    @State private var isResending = false
    @State private var isAutoVerifying = false

    // MARK: - Initialization
    init(
        email: String,
        password: String,
        isFromLogin: Bool,
        contentOpacity: Binding<Double>,
        backgroundHeight: Binding<CGFloat>,
        backgroundWidth: Binding<CGFloat>,
        isAnimating: Binding<Bool>,
        onBack: @escaping () -> Void,
        username: String = ""
    ) {
        _viewModel = State(
            initialValue: VerificationViewModel(
                email: email,
                password: password,
                isFromLogin: isFromLogin,
                username: username))
        _contentOpacity = contentOpacity
        _backgroundHeight = backgroundHeight
        _backgroundWidth = backgroundWidth
        _isAnimating = isAnimating
        self.password = password
        self.viewModel.onBack = onBack
    }

    // MARK: - Body View
    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 20) {
                Button(action: {
                    viewModel.onBack()
                }) {
                    Image(systemName: "arrow.left")
                        .font(.title)
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.leading, 21)

                Text("Confirmation")
                    .font(.system(size: 40, weight: .medium))
                    .lineSpacing(62.93)
                    .padding(.leading, 21)

                Text("The code has been sent to %@".localized(viewModel.email))
                .foregroundColor(.gray)
                .padding(.leading, 21)
                .padding(.top, 8)

                HStack(spacing: 12) {
                    ForEach(0..<6) { index in
                        PasteableTextField(
                            text: $viewModel.verificationCode[index],
                            index: index,
                            onPaste: { pastedCode in
                                // Update code immediately
                                viewModel.pasteCode(pastedCode)
                                // Check after a brief moment to allow UI to update
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    let fullCode = viewModel.verificationCode.joined()
                                    if fullCode.count == 6 && fullCode.allSatisfy({ $0.isNumber }) && !isAutoVerifying && !isLoading {
                                        isAutoVerifying = true
                                        Task {
                                            isLoading = true
                                            if let userData = await viewModel.verifyCode() {
                                                viewModel.saveUserData(userData)
                                                routingViewModel.navigateToScreen(.chats)
                                            } else if let error = viewModel.errorMessage {
                                                errorMessage = error
                                                showError = true
                                            }
                                            isAutoVerifying = false
                                            isLoading = false
                                        }
                                    }
                                }
                            }
                        )
                        .frame(width: 45, height: 45)
                        .focused($focusedField, equals: index)
                        .onChange(of: viewModel.verificationCode[index]) { oldValue, newValue in
                            if let nextField = viewModel.handleCodeInput(
                                at: index, newValue: newValue) {
                                focusedField = nextField
                            }
                            
                            // Auto-verify when all 6 digits are entered
                            let fullCode = viewModel.verificationCode.joined()
                            if fullCode.count == 6 && fullCode.allSatisfy({ $0.isNumber }) && !isAutoVerifying && !isLoading {
                                isAutoVerifying = true
                                Task {
                                    isLoading = true
                                    if let userData = await viewModel.verifyCode() {
                                        viewModel.saveUserData(userData)
                                        routingViewModel.navigateToScreen(.chats)
                                    } else if let error = viewModel.errorMessage {
                                        errorMessage = error
                                        showError = true
                                    }
                                    isAutoVerifying = false
                                    isLoading = false
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
                .padding(.horizontal, 21)

                Button(action: {
                    guard !isLoading && !isAutoVerifying else { return }
                    Task {
                        isLoading = true
                        if let userData = await viewModel.verifyCode() {
                            viewModel.saveUserData(userData)
                            routingViewModel.navigateToScreen(.chats)
                        } else if let error = viewModel.errorMessage {
                            errorMessage = error
                            showError = true
                        }
                        isLoading = false
                    }
                }) {
                    Text("Confirm")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.black)
                        .cornerRadius(8)
                }
                .padding(.horizontal, 21)
                .padding(.top, 32)
                .alert("Ошибка", isPresented: $showError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(errorMessage)
                }

                Button(action: {
                    Task {
                        isResending = true
                        await viewModel.resendCode()
                        if let error = viewModel.errorMessage {
                            errorMessage = error
                            showError = true
                        }
                        isResending = false
                    }
                }) {
                    Text(
                        viewModel.canResendCode
                            ? "Send the code again".localized
                            : "Send again in %@".localized(viewModel.formattedTime)
                    )
                    .foregroundColor(viewModel.canResendCode ? .black : .gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                .disabled(!viewModel.canResendCode)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: "#CADDAD"))

            if isLoading || isResending {
                LoadingView()
            }
        }
        .onAppear {
            viewModel.startTimer()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
    }
}

// MARK: - Preview
#Preview {
    VerificationView(
        email: "",
        password: "",
        isFromLogin: true,
        contentOpacity: .constant(0),
        backgroundHeight: .constant(UIScreen.main.bounds.height),
        backgroundWidth: .constant(UIScreen.main.bounds.width),
        isAnimating: .constant(true),
        onBack: {}
    )
}
