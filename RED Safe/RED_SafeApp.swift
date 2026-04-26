import SwiftUI
import UIKit

@main
struct RED_SafeApp: App {
    @StateObject private var auth = AuthManager.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootRouter()
                .environmentObject(auth)
                .onAppear {
                    NetworkMonitor.shared.start()
                    auth.bootstrap()
                }
        }
    }
}

/// 由 OrientationLock 動態決定支援的方向,讓即時影像頁可橫向、其他頁維持直向。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLock.shared.mask
    }
}

private struct RootRouter: View {
    @EnvironmentObject private var auth: AuthManager
    @State private var showSplashOverlay = true
    @AppStorage("appAppearance") private var appearanceSelection = AppearanceMode.system.rawValue

    private var currentAppearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceSelection) ?? .system
    }

    var body: some View {
        ZStack {
            switch auth.phase {
            case .launching, .refreshing:
                LoadView()
            case .authenticated:
                HomeView()
            case .signedOut:
                SignInView()
            }

            if showSplashOverlay {
                LoadView()
                    .transition(.opacity)
            }
        }
        .onChange(of: auth.phase) { newPhase in
            guard showSplashOverlay else { return }
            if newPhase == .authenticated || newPhase == .signedOut {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    withAnimation(.easeOut(duration: 0.35)) {
                        showSplashOverlay = false
                    }
                }
            }
        }
        .preferredColorScheme(currentAppearance.colorScheme)
    }
}
