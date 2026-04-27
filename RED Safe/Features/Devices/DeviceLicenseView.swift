import SwiftUI

struct DeviceLicenseView: View {
    let edge: EdgeSummary

    @State private var licenseInfo: LicenseInfoResponse?
    @State private var isLoading = false
    @State private var showActivation = false

    private var hasValidLicense: Bool {
        guard let info = licenseInfo else { return false }
        return info.errorCode.isSuccess
            && (info.licensed == true || info.status?.lowercased() == "active")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                pageHeader

                if !isLoading && !hasValidLicense {
                    noLicenseBanner
                }

                licenseDetail
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .background(Color.appBackground)
        .navigationTitle("授權資訊")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { await loadLicense() }
        .sheet(isPresented: $showActivation) {
            LicenseActivationView(
                edgeId: edge.edgeId,
                edgePassword: "",
                onActivated: {
                    Task { await loadLicense() }
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Data

    private func loadLicense() async {
        isLoading = true
        defer { isLoading = false }
        do {
            licenseInfo = try await APIClient.shared.fetchEdgeLicense(edgeId: edge.edgeId)
        } catch {
            licenseInfo = nil
        }
    }

    // MARK: - Page Header

    private var pageHeader: some View {
        GlassContainer(padding: 0) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.primaryBrand.opacity(0.1))
                        .frame(width: 56, height: 56)
                    Image(systemName: "key.fill")
                        .font(.title2)
                        .foregroundStyle(Color.primaryBrand)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("授權管理")
                        .font(.bodyLarge.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text(edge.edgeId)
                        .font(.captionText.monospaced())
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
            }
            .padding(20)
        }
    }

    // MARK: - No License Banner

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
                        showActivation = true
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

    // MARK: - License Detail

    private var licenseDetail: some View {
        GlassContainer(padding: 20) {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView().tint(.primaryBrand)
                    Spacer()
                }
                .padding(.vertical, 12)
            } else if let info = licenseInfo, info.errorCode.isSuccess {
                VStack(spacing: 14) {
                    infoRow(icon: "doc.text", title: "方案", value: info.planName ?? "—")
                    Divider().background(Color.border)
                    infoRow(
                        icon: "checkmark.seal",
                        title: "狀態",
                        value: localizedStatus(info.status),
                        valueColor: statusColor(info.status)
                    )
                    Divider().background(Color.border)
                    infoRow(icon: "calendar", title: "啟用時間", value: formatDate(info.activatedAt))
                    Divider().background(Color.border)
                    infoRow(icon: "calendar.badge.clock", title: "到期時間", value: formatDate(info.expiresAt))
                    Divider().background(Color.border)
                    infoRow(icon: "camera", title: "最大攝影機數", value: info.maxCameras.map { "\($0)" } ?? "—")
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
                            showActivation = true
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Helpers

    private func infoRow(icon: String, title: String, value: String, valueColor: Color = .textPrimary) -> some View {
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

    private func localizedStatus(_ status: String?) -> String {
        switch status?.lowercased() {
        case "active": return "有效"
        case "expired": return "已過期"
        case "revoked": return "已撤銷"
        default: return status ?? "未知"
        }
    }

    private func statusColor(_ status: String?) -> Color {
        switch status?.lowercased() {
        case "active": return .successGreen
        case "expired": return .warningOrange
        case "revoked": return .errorRed
        default: return .textSecondary
        }
    }

    private func formatDate(_ dateString: String?) -> String {
        RedSafeDateFormatter.displayAbsolute(from: dateString)
    }
}
