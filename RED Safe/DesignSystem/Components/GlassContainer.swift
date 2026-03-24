import SwiftUI

struct GlassContainer<Content: View>: View {
    var padding: CGFloat = 24
    let content: Content
    
    init(padding: CGFloat = 24, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.border, lineWidth: 1)
            )
            .shadow(color: Color.shadowSubtle, radius: 20, x: 0, y: 10)
    }
}
