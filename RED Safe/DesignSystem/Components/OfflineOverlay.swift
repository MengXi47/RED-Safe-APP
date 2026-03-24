import SwiftUI

/// 裝置離線時的遮罩層
struct OfflineOverlay: View {
    var body: some View {
        ZStack {
            // 背景半透明灰
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            // 提示內容
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
                    Text("裝置已離線")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)
                    Text("目前無法讀取或修改設定\n請檢查裝置連線狀態")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(40)
            .background(.ultraThinMaterial) // 加一點磨砂質感
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 40)
        }
    }
}

extension View {
    /// 當裝置離線時顯示遮罩
    /// - Parameter isOnline: 裝置是否在線 (可為 nil，視為離線或處理中，但此處主要針對明確 false)
    func offlineOverlay(isOnline: Bool?) -> some View {
        ZStack {
            self
            
            if isOnline == false {
                OfflineOverlay()
            }
        }
    }
}
