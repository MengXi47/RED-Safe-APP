import SwiftUI

struct SecondaryButton: View {
    let title: String
    let icon: String?
    var fullWidth: Bool = true
    let action: () -> Void
    
    init(_ title: String, icon: String? = nil, fullWidth: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.fullWidth = fullWidth
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.headline)
                }
                Text(title)
                    .font(.buttonText)
            }
            .foregroundColor(.primaryBrand)
            .padding(.vertical, 16)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primaryBrand.opacity(0.1))
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}
