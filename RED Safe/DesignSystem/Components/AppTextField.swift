import SwiftUI

struct AppTextField: View {
    let title: String
    @Binding var text: String
    var icon: String? = nil
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var errorMessage: String? = nil

    // 真實鍵盤焦點 — 取代舊版 @State isFocused 與 .onTapGesture 的拼湊做法，
    // 那會吞掉 TextField 的第一次點擊，導致需要連點兩三下才能輸入。
    @FocusState private var isFocused: Bool
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
                        .focused($isFocused)
                } else {
                    TextField(title, text: $text)
                        .keyboardType(keyboardType)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($isFocused)
                }

                if isSecure {
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundColor(.textSecondary)
                    }
                    .buttonStyle(.plain)
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
                    .stroke(
                        errorMessage != nil
                            ? Color.errorRed
                            : (isFocused ? Color.primaryBrand : Color.border),
                        lineWidth: 1.5
                    )
            )
            // 點擊整個欄位內距時也聚焦到輸入框；TextField 本身的 hit-test 優先，
            // 所以直接點到輸入區域時不會走到這裡，不會搶走第一次點擊。
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }

            if let errorMessage {
                Text(errorMessage)
                    .font(.captionText)
                    .foregroundColor(.errorRed)
                    .padding(.leading, 4)
            }
        }
    }
}
