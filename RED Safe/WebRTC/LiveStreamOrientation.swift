// 控制即時影像頁面的旋轉行為。
// 依照 INFOPLIST_KEY_UISupportedInterfaceOrientations 設定,iPhone 預設只允許 Portrait;
// 這個 helper 在 LiveStreamView 出現時放寬到 .allButUpsideDown,離開時收回去。

import SwiftUI
import UIKit

/// 全域單例,持有目前頁面允許的方向遮罩。
/// `RED_SafeApp` 透過 `UIApplicationDelegateAdaptor` 注入 `AppDelegate`,
/// 由 AppDelegate 的 `application(_:supportedInterfaceOrientationsFor:)` 讀取此值。
final class OrientationLock {
    static let shared = OrientationLock()
    private init() {}

    private(set) var mask: UIInterfaceOrientationMask = .portrait

    /// 設定允許的方向遮罩,並請系統重新評估。
    func setMask(_ mask: UIInterfaceOrientationMask, rotateTo orientation: UIInterfaceOrientation? = nil) {
        self.mask = mask
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }

        if #available(iOS 16.0, *) {
            let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
            scene.requestGeometryUpdate(prefs) { _ in }
            scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        } else if let orientation {
            UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}

/// SwiftUI ViewModifier:出現時放寬方向、消失時收回。
struct AllowedOrientationsModifier: ViewModifier {
    let mask: UIInterfaceOrientationMask

    func body(content: Content) -> some View {
        content
            .onAppear { OrientationLock.shared.setMask(mask) }
            .onDisappear { OrientationLock.shared.setMask(.portrait) }
    }
}

extension View {
    func allowedOrientations(_ mask: UIInterfaceOrientationMask) -> some View {
        modifier(AllowedOrientationsModifier(mask: mask))
    }
}
