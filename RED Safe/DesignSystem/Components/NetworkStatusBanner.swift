import SwiftUI

/// App 層級的網路狀態橫幅：離線時固定顯示於畫面頂端，恢復後自動消失。
struct NetworkStatusBanner: View {
    let isConnected: Bool

    var body: some View {
        if !isConnected {
            HStack(spacing: 10) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 15, weight: .semibold))
                Text("目前沒有網路連線")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(Color.orange.gradient)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

extension View {
    /// 在畫面頂端疊加網路狀態橫幅，離線時自動顯示。
    /// 直接讀取 NetworkMonitor.shared.isConnected，SwiftUI @Observable 追蹤自動生效。
    func networkStatusBanner() -> some View {
        VStack(spacing: 0) {
            NetworkStatusBanner(isConnected: NetworkMonitor.shared.isConnected)
            self
        }
        .animation(.easeInOut(duration: 0.3), value: NetworkMonitor.shared.isConnected)
    }
}
