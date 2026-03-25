import SwiftUI

/// Edge 詳細頁面：提供裝置資訊、配置連結與管理操作。
struct DeviceDetailView: View {
    let edge: EdgeSummary
    let rename: () -> Void
    let updatePassword: () -> Void
    let unbind: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                infoCard
                configurationCard
                managementCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 32)
        }
        .background(Color.appBackground)
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle((edge.displayName ?? "").isEmpty ? edge.edgeId : edge.displayName!)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private var infoCard: some View {
        GlassContainer(padding: 24) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text((edge.displayName ?? "").isEmpty ? "未命名裝置" : edge.displayName!)
                            .font(.displaySmall)
                            .foregroundStyle(Color.textPrimary)
                        Text(edge.edgeId)
                            .font(.bodyMedium.monospaced())
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(Color.primaryBrand.opacity(0.1))
                            .frame(width: 48, height: 48)
                        Image(systemName: "server.rack")
                            .font(.title3)
                            .foregroundStyle(Color.primaryBrand)
                    }
                }

                Divider().background(Color.border)

                let online = edge.isOnline ?? false
                let statusColor = online ? Color.successGreen : Color.errorRed
                let statusIcon = online ? "wifi" : "wifi.slash"
                let statusText = online ? "裝置在線" : "裝置離線"

                HStack(spacing: 12) {
                    Image(systemName: statusIcon)
                        .font(.bodyLarge)
                        .foregroundStyle(statusColor)
                    Text(statusText)
                        .font(.bodyLarge.weight(.medium))
                        .foregroundStyle(statusColor)
                    Spacer()
                }
                .padding(12)
                .background(statusColor.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }

    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("裝置配置")
                .font(.bodyLarge.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 4)

            GlassContainer(padding: 0) {
                VStack(spacing: 0) {
                    NavigationLink {
                        NetworkConfigView(edge: edge)
                    } label: {
                        rowContent(icon: "network", title: "網路配置")
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 52).background(Color.border)

                    NavigationLink {
                        IPCameraConfigView(edge: edge)
                    } label: {
                        rowContent(icon: "camera.fill", title: "IP Camera 配置")
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 52).background(Color.border)

                    NavigationLink {
                        DetectionPoliciesView(edge: edge)
                    } label: {
                        rowContent(icon: "shield.checkered", title: "偵測策略")
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 52).background(Color.border)

                    NavigationLink {
                        GeminiConfigView(edge: edge)
                    } label: {
                        rowContent(icon: "brain.head.profile", title: "AI 輔助偵測")
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 52).background(Color.border)

                    NavigationLink {
                        LiveStreamView(edge: edge)
                    } label: {
                        rowContent(icon: "video.fill", title: "即時影像")
                    }
                    .buttonStyle(.plain)

                }
                .padding(.vertical, 8)
            }
        }
    }

    private var managementCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("裝置管理")
                .font(.bodyLarge.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 4)

            GlassContainer(padding: 0) {
                VStack(spacing: 0) {
                    NavigationLink {
                        DeviceLicenseView(edge: edge)
                    } label: {
                        rowContent(icon: "key.fill", title: "授權資訊")
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 52).background(Color.border)

                    Button(action: rename) {
                        rowContent(icon: "pencil.line", title: "重新命名")
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 52).background(Color.border)

                    Button(action: updatePassword) {
                        rowContent(icon: "lock.rotation", title: "更新 Edge 密碼")
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 52).background(Color.border)

                    Button(action: unbind) {
                        rowContent(icon: "link.badge.minus", title: "解除綁定", isDestructive: true)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func rowContent(icon: String, title: String, isDestructive: Bool = false) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.bodyLarge)
                .foregroundStyle(isDestructive ? Color.errorRed : Color.textSecondary)
                .frame(width: 24)
            Text(title)
                .font(.bodyMedium)
                .foregroundStyle(isDestructive ? Color.errorRed : Color.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}
