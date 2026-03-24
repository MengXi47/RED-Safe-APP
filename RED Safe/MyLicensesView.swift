import SwiftUI

/// 我的授權：顯示使用者所有授權金鑰的清單與狀態。
struct MyLicensesView: View {
    @State private var licenses: [UserLicense] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    headerSection
                    contentSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .navigationTitle("我的授權")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadLicenses()
        }
        .refreshable {
            await loadLicenses()
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("我的授權")
                .font(.displaySmall)
                .foregroundStyle(Color.textPrimary)
            Text("查看所有授權金鑰的狀態與綁定資訊")
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var contentSection: some View {
        Group {
            if isLoading && licenses.isEmpty {
                loadingView
            } else if let errorMessage {
                errorView(message: errorMessage)
            } else if licenses.isEmpty {
                emptyView
            } else {
                licenseList
            }
        }
    }

    private var loadingView: some View {
        GlassContainer(padding: 24) {
            HStack {
                Spacer()
                ProgressView()
                    .tint(.primaryBrand)
                Text("正在載入...")
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
            }
        }
    }

    private func errorView(message: String) -> some View {
        GlassContainer(padding: 20) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.warningOrange)
                Text(message)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 18) {
            Image(systemName: "key.slash")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
                .padding(.top, 40)
            Text("尚無任何授權")
                .font(.title3)
                .foregroundStyle(Color.textPrimary)
            Text("您可以前往官方網站購買授權方案。")
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                if let url = URL(string: "https://introducing.redsafe-tw.com/pricing") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "cart.fill")
                    Text("購買授權")
                        .font(.buttonText)
                }
                .foregroundColor(.white)
                .padding(.vertical, 14)
                .padding(.horizontal, 32)
                .background(
                    Capsule()
                        .fill(Color.primaryGradient)
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var licenseList: some View {
        LazyVStack(spacing: 16) {
            ForEach(licenses) { license in
                LicenseCard(license: license)
            }
        }
    }

    // MARK: - Data

    private func loadLicenses() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            licenses = try await APIClient.shared.fetchUserLicenses()
        } catch {
            // Ignore task/request cancellation — keep existing data
            if Task.isCancelled { return }
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - License Card

private struct LicenseCard: View {
    let license: UserLicense

    var body: some View {
        GlassContainer(padding: 20) {
            VStack(spacing: 14) {
                // Header
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: statusIcon)
                        .font(.title3)
                        .foregroundStyle(statusColor)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(license.planName ?? "未知方案")
                            .font(.bodyLarge.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text(license.licenseKey)
                            .font(.captionText.monospaced())
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer()

                    Text(localizedStatus)
                        .font(.captionText.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.12))
                        .cornerRadius(8)
                }

                Divider().background(Color.border)

                // Details
                VStack(spacing: 10) {
                    let effectiveBoundEdgeId = license.boundEdgeId ?? license.edgeId
                    if let edgeId = effectiveBoundEdgeId, !edgeId.isEmpty {
                        detailRow(
                            icon: "server.rack",
                            title: "綁定裝置",
                            value: license.edgeName?.isEmpty == false ? "\(license.edgeName!) (\(edgeId))" : edgeId
                        )
                    } else {
                        detailRow(icon: "server.rack", title: "綁定裝置", value: "尚未綁定")
                    }

                    if let maxCameras = license.maxCameras {
                        detailRow(icon: "camera", title: "最大攝影機數", value: "\(maxCameras)")
                    }

                    if let activatedAt = license.activatedAt {
                        detailRow(icon: "calendar", title: "啟用時間", value: formatDate(activatedAt))
                    }

                    if let expiresAt = license.expiresAt {
                        detailRow(icon: "calendar.badge.clock", title: "到期時間", value: formatDate(expiresAt))
                    }
                }
            }
        }
    }

    private func detailRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 16)
            Text(title)
                .font(.captionText)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.captionText.weight(.medium))
                .foregroundStyle(Color.textPrimary)
        }
    }

    private var localizedStatus: String {
        switch license.status?.lowercased() {
        case "active": return "有效"
        case "expired": return "已過期"
        case "revoked": return "已撤銷"
        case "unbound": return "未綁定"
        default: return license.status ?? "未知"
        }
    }

    private var statusColor: Color {
        switch license.status?.lowercased() {
        case "active": return .successGreen
        case "expired": return .warningOrange
        case "revoked": return .errorRed
        case "unbound": return .primaryBrand
        default: return .textSecondary
        }
    }

    private var statusIcon: String {
        switch license.status?.lowercased() {
        case "active": return "checkmark.seal.fill"
        case "expired": return "clock.badge.exclamationmark"
        case "revoked": return "xmark.seal.fill"
        case "unbound": return "key"
        default: return "questionmark.circle"
        }
    }

    private func formatDate(_ dateString: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "yyyy/MM/dd HH:mm"
        displayFormatter.timeZone = TimeZone(identifier: "Asia/Taipei")

        if let date = isoFormatter.date(from: dateString) {
            return displayFormatter.string(from: date)
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: dateString) {
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}
