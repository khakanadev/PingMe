import SwiftUI

struct PasswordField: View {
    @Binding var text: String
    @State private var isPasswordVisible = false
    var placeholder: String = ""
    var onValidate: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 0) {
            Group {
                if isPasswordVisible {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .onChange(of: text) { _, _ in
                onValidate?()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Button(action: {
                isPasswordVisible.toggle()
            }) {
                Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                    .foregroundColor(.black)
                    .font(.system(size: 16, weight: .regular))
            }
            .padding(.trailing, 8)
            .buttonStyle(PlainButtonStyle())
        }
    }
}

