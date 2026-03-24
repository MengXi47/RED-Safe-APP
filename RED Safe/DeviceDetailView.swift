import SwiftUI

/// Edge 詳細頁面：提供裝置資訊、配置連結與管理操作。
struct DeviceDetailView: View {
    let edge: EdgeSummary
    let rename: () -> Void
    let updatePassword: () -> Void
    let unbind: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var licenseInfo: LicenseInfoResponse?
    @State private var isLoadingLicense = false
    @State private var showLicenseActivation = false
    @State private var showNoLicenseAlert = false

    /// 授權是否有效（用於顯示警告橫幅）
    private var hasValidLicense: Bool {
        guard let info = licenseInfo else { return false }
        return info.errorCode.isSuccess
            && (info.licensed == true || info.status?.lowercased() == "active")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                infoCard

                if !isLoadingLicense && !hasValidLicense {
                    noLicenseBanner
                }

                licenseCard
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
        .task {
            await loadLicense()
        }
        .sheet(isPresented: $showLicenseActivation) {
            LicenseActivationView(
                edgeId: edge.edgeId,
                edgePassword: "",
                onActivated: {
                    Task { await loadLicense() }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .alert("無法執行指令", isPresented: $showNoLicenseAlert) {
            Button("購買授權") {
                if let url = URL(string: "https://introducing.redsafe-tw.com/pricing") {
                    UIApplication.shared.open(url)
                }
            }
            Button("知道了", role: .cancel) {}
        } message: {
            Text("此裝置尚無有效授權，無法執行指令。請至 introducing.redsafe-tw.com 購買授權。")
        }
    }

    private func loadLicense() async {
        isLoadingLicense = true
        defer { isLoadingLicense = false }
        do {
            licenseInfo = try await APIClient.shared.fetchEdgeLicense(edgeId: edge.edgeId)
        } catch {
            licenseInfo = nil
        }
    }

    private var noLicenseBanner: some View {
        GlassContainer(padding: 16) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.title3)
                        .foregroundStyle(Color.warningOrange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("尚無有效授權")
                            .font(.bodyMedium.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("此裝置無法執行指令，請購買或啟用授權。")
                            .font(.captionText)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer()
                }

                HStack(spacing: 12) {
                    Button {
                        if let url = URL(string: "https://introducing.redsafe-tw.com/pricing") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "cart.fill")
                                .font(.caption)
                            Text("購買授權")
                                .font(.captionText.weight(.semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.primaryBrand)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showLicenseActivation = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "key.fill")
                                .font(.caption)
                            Text("啟用金鑰")
                                .font(.captionText.weight(.semibold))
                        }
                        .foregroundColor(.primaryBrand)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.primaryBrand.opacity(0.1))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
            }
        }
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

    private var licenseCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("授權資訊")
                .font(.bodyLarge.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 4)

            GlassContainer(padding: 20) {
                if isLoadingLicense {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(.primaryBrand)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                } else if let info = licenseInfo, info.errorCode.isSuccess {
                    VStack(spacing: 14) {
                        licenseRow(icon: "doc.text", title: "方案", value: info.planName ?? "—")
                        Divider().background(Color.border)
                        licenseRow(
                            icon: "checkmark.seal",
                            title: "狀態",
                            value: localizedLicenseStatus(info.status),
                            valueColor: licenseStatusColor(info.status)
                        )
                        Divider().background(Color.border)
                        licenseRow(icon: "calendar", title: "啟用時間", value: formatLicenseDate(info.activatedAt))
                        Divider().background(Color.border)
                        licenseRow(icon: "calendar.badge.clock", title: "到期時間", value: formatLicenseDate(info.expiresAt))
                        Divider().background(Color.border)
                        licenseRow(icon: "camera", title: "最大攝影機數", value: info.maxCameras.map { "\($0)" } ?? "—")
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "key.slash")
                            .font(.title2)
                            .foregroundStyle(Color.textTertiary)
                        Text("未授權")
                            .font(.bodyMedium.weight(.medium))
                            .foregroundStyle(Color.textSecondary)
                        Text("此裝置尚無有效授權，請購買或啟用授權金鑰。")
                            .font(.captionText)
                            .foregroundStyle(Color.textTertiary)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 12) {
                            Button {
                                if let url = URL(string: "https://introducing.redsafe-tw.com/pricing") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "cart.fill")
                                        .font(.headline)
                                    Text("購買授權")
                                        .font(.buttonText)
                                }
                                .foregroundColor(.white)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.primaryGradient)
                                )
                            }
                            .buttonStyle(ScaleButtonStyle())

                            SecondaryButton("啟用金鑰", icon: "key.fill") {
                                showLicenseActivation = true
                            }
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func licenseRow(icon: String, title: String, value: String, valueColor: Color = .textPrimary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 20)
            Text(title)
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.bodyMedium.weight(.medium))
                .foregroundStyle(valueColor)
        }
    }

    private func localizedLicenseStatus(_ status: String?) -> String {
        switch status?.lowercased() {
        case "active": return "有效"
        case "expired": return "已過期"
        case "revoked": return "已撤銷"
        default: return status ?? "未知"
        }
    }

    private func licenseStatusColor(_ status: String?) -> Color {
        switch status?.lowercased() {
        case "active": return .successGreen
        case "expired": return .warningOrange
        case "revoked": return .errorRed
        default: return .textSecondary
        }
    }

    private func formatLicenseDate(_ dateString: String?) -> String {
        guard let dateString, !dateString.isEmpty else { return "—" }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "yyyy/MM/dd HH:mm"
        displayFormatter.timeZone = TimeZone(identifier: "Asia/Taipei")

        if let date = isoFormatter.date(from: dateString) {
            return displayFormatter.string(from: date)
        }
        // Fallback: try without fractional seconds
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: dateString) {
            return displayFormatter.string(from: date)
        }
        return dateString
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
