import SwiftUI

/// HomeView：主頁面框架，包含底部導覽列與子頁面容器。
struct HomeView: View {
    @EnvironmentObject var auth: AuthManager
    
    // ViewModels are owned here to survive tab switching
    @StateObject private var homeVM = HomeViewModel()
    @StateObject private var profileVM = ProfileViewModel()
    
    // Tab selection state
    @State private var selection: Tab = .dashboard
    
    // Animation states
    @State private var animateBackground = false

    // Dashboard navigation bindings
    @State private var deviceSheet: DeviceSheet?
    @State private var deviceToUnbind: EdgeSummary?
    @State private var showUnbindConfirm = false
    
    // Account bindings
    @State private var profileSheet: ProfileSheet?

    enum Tab {
        case dashboard
        case account
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Global Background
            // Passed animateBackground binding if Dashboard wants to trigger animations
            Color.appBackground.ignoresSafeArea()

            // Main Content
            TabView(selection: $selection) {
                DashboardView(
                    homeVM: homeVM,
                    auth: auth,
                    deviceSheet: $deviceSheet,
                    deviceToUnbind: $deviceToUnbind,
                    showUnbindConfirm: $showUnbindConfirm,
                    animateBackground: $animateBackground
                )
                .tag(Tab.dashboard)
                .tabItem {
                    Label("總覽", systemImage: "square.grid.2x2.fill")
                }

                AccountView(
                    auth: auth,
                    profileVM: profileVM,
                    profileSheet: $profileSheet
                )
                .tag(Tab.account)
                .tabItem {
                    Label("帳號", systemImage: "person.crop.circle.fill")
                }
            }
            .tint(Color.primaryBrand)
            
            // Global Toast Overlay
            if homeVM.showMessage, let msg = homeVM.message {
                ToastOverlay(message: msg, icon: "info.circle.fill")
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
                    .padding(.bottom, 60) // Lift above tab bar slightly if needed, or top
            }
            
            if profileVM.showMessage, let msg = profileVM.message {
                ToastOverlay(message: msg, icon: "checkmark.circle.fill")
                     .transition(.move(edge: .top).combined(with: .opacity))
                     .zIndex(100)
                     .padding(.bottom, 60)
            }
        }
        .onAppear {
            // Initial Data Load
            homeVM.loadEdges()
            Task { await auth.refreshProfileFromRemote() }
        }
    }
}

// MARK: - Components

private struct ToastOverlay: View {
    let message: String
    let icon: String
    
    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.bodyLarge)
                Text(message)
                    .font(.bodyMedium)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(Color.textPrimary.opacity(0.9))
                    .shadow(color: .shadowSubtle, radius: 10, x: 0, y: 5)
            )
            .padding(.top, 60) // Show at top
            
            Spacer()
        }
        .animation(.spring(), value: message)
    }
}
