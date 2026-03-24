import SwiftUI

struct PrimaryButton: View {
    let title: String
    let icon: String?
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void
    
    init(_ title: String, icon: String? = nil, isLoading: Bool = false, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primaryGradient)
                    .opacity(isDisabled ? 0.5 : 1)
                
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else if let icon {
                        Image(systemName: icon)
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    
                    Text(title)
                        .font(.buttonText)
                        .foregroundColor(.white)
                }
                .padding(.vertical, 16)
            }
            .frame(height: 56)
            .shadow(color: isDisabled ? .clear : Color.primaryBrand.opacity(0.4), radius: 10, x: 0, y: 8)
            .scaleEffect(isDisabled ? 1.0 : 1.0) // Placeholder for press effect if added later
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(isDisabled || isLoading)
    }
}
