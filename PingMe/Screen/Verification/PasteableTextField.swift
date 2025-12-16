import SwiftUI
import UIKit

// Custom UITextField that intercepts paste operations
class PasteableUITextField: UITextField {
    var onPasteAction: ((String) -> Void)?
    
    override func paste(_ sender: Any?) {
        // Get pasteboard content
        let pasteboard = UIPasteboard.general
        if let pastedString = pasteboard.string {
            // Extract digits from pasted string
            let digits = pastedString.filter { $0.isNumber }.prefix(6)
            if !digits.isEmpty {
                // Call onPaste to distribute across all fields
                onPasteAction?(String(digits))
                // Don't call super.paste to prevent inserting text into this field
                return
            }
        }
        // If no digits found, don't paste anything
    }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(UIResponderStandardEditActions.paste(_:)) {
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }
}

struct PasteableTextField: UIViewRepresentable {
    @Binding var text: String
    let index: Int
    let onPaste: (String) -> Void
    
    func makeUIView(context: Context) -> UITextField {
        let textField = PasteableUITextField()
        textField.delegate = context.coordinator
        textField.keyboardType = .numberPad
        textField.textAlignment = .center
        textField.font = .systemFont(ofSize: 24, weight: .regular)
        textField.backgroundColor = UIColor(hex: "#CADDAD")
        textField.layer.cornerRadius = 8
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UIColor.black.cgColor
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textFieldDidChange), for: .editingChanged)
        // Store reference to onPaste in coordinator
        context.coordinator.onPasteCallback = onPaste
        textField.onPasteAction = { [weak coordinator = context.coordinator] pastedCode in
            // Call onPaste on main thread
            DispatchQueue.main.async {
                coordinator?.onPasteCallback?(pastedCode)
            }
        }
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        // Update text field to match binding
        // Check if text changed to avoid unnecessary updates
        let currentText = uiView.text ?? ""
        if currentText != text {
            uiView.text = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        let parent: PasteableTextField
        var onPasteCallback: ((String) -> Void)?
        
        init(_ parent: PasteableTextField) {
            self.parent = parent
            self.onPasteCallback = parent.onPaste
        }
        
        @objc func textFieldDidChange(_ textField: UITextField) {
            // Only update if it's a single character (not paste)
            if let text = textField.text, text.count <= 1 {
                parent.text = text
            }
        }
        
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            // Handle paste or autofill: if string contains multiple characters or non-digit characters, extract digits
            if string.count > 1 || !string.allSatisfy({ $0.isNumber }) {
                // Extract all digits from the string (handles cases like "Источник gmail - 041159")
                let allDigits = string.filter { $0.isNumber }
                if allDigits.count >= 1 {
                    // If we have multiple digits, paste them all
                    if allDigits.count > 1 {
                        let digits = String(allDigits.prefix(6))
                        // Call onPaste synchronously to ensure immediate update
                        if Thread.isMainThread {
                            self.parent.onPaste(digits)
                        } else {
                            DispatchQueue.main.sync {
                                self.parent.onPaste(digits)
                            }
                        }
                        // Clear current field to prevent showing first digit
                        textField.text = ""
                        return false // Don't insert the text normally
                    } else {
                        // Single digit, but from a string with other characters - extract just the digit
                        let digit = String(allDigits.prefix(1))
                        textField.text = digit
                        parent.text = digit
                        return false
                    }
                } else {
                    // No digits found, reject
                    return false
                }
            }
            
            // Handle single digit input
            let currentText = textField.text ?? ""
            let newText = (currentText as NSString).replacingCharacters(in: range, with: string)
            
            // Only allow digits
            if !newText.isEmpty && !newText.allSatisfy({ $0.isNumber }) {
                return false
            }
            
            // Limit to 1 character per field
            if newText.count > 1 {
                return false
            }
            
            return true
        }
    }
}

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let alpha, red, green, blue: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (alpha, red, green, blue) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (alpha, red, green, blue) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (alpha, red, green, blue) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (alpha, red, green, blue) = (255, 0, 0, 0)
        }
        self.init(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: CGFloat(alpha) / 255)
    }
}

