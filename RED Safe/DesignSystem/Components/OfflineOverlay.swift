import SwiftUI

/// 裝置離線或 App 無網路時的遮罩層
struct OfflineOverlay: View {
    var appIsOffline: Bool = false

    private var title: String {
        appIsOffline ? "沒有網路連線" : "裝置已離線"
    }

    private var subtitle: String {
        appIsOffline
            ? "目前沒有網路連線\n請檢查手機連線狀態"
            : "目前無法讀取或修改設定\n請檢查裝置連線狀態"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 80, height: 80)

                    Image(systemName: "wifi.slash")
                        .font(.system(size: 36))
                        .foregroundColor(.white)
                }

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(40)
            .background(.ultraThinMaterial)
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 40)
        }
    }
}

extension View {
    /// 當裝置離線或 App 無網路時顯示遮罩。
    /// 直接讀取 NetworkMonitor.shared.isConnected，SwiftUI 的 @Observable 追蹤自動生效。
    func offlineOverlay(isOnline: Bool?) -> some View {
        ZStack {
            self

            // App 自身離線（優先顯示）
            if !NetworkMonitor.shared.isConnected {
                OfflineOverlay(appIsOffline: true)
            } else if isOnline == false {
                OfflineOverlay()
            }
        }
    }
}
