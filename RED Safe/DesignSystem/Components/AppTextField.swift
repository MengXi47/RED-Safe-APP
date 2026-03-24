import SwiftUI

struct AppTextField: View {
    let title: String
    @Binding var text: String
    var icon: String? = nil
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var errorMessage: String? = nil
    
    @State private var isFocused: Bool = false
    @State private var showPassword: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .foregroundColor(isFocused ? .primaryBrand : .textSecondary)
                        .font(.bodyMedium)
                        .frame(width: 20)
                }
                
                if isSecure && !showPassword {
                    SecureField(title, text: $text)
                        .textContentType(.password)
                } else {
                    TextField(title, text: $text)
                        .keyboardType(keyboardType)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                
                if isSecure {
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(errorMessage != nil ? Color.errorRed : (isFocused ? Color.primaryBrand : Color.border), lineWidth: 1.5)
            )
            // Using onEditingChanged modification wrapper if needed, or simply FocusState in parent. 
            // For simplicity here, we rely on parent FocusState or just visual feedback.
            // But to track internal focus for color:
            .onTapGesture { isFocused = true } // Simple fallback
            
            if let errorMessage {
                Text(errorMessage)
                    .font(.captionText)
                    .foregroundColor(.errorRed)
                    .padding(.leading, 4)
            }
        }
    }
}
