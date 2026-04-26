import SwiftUI

/// 通用按壓回饋:輕微縮放 + 彈簧動畫,用於整套 App 的卡片型 Button / NavigationLink。
/// 從 DashboardView 抽出統一管理,避免跨檔案隱性依賴。
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(), value: configuration.isPressed)
    }
}
