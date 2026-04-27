import SwiftUI

/// 授權金鑰啟用頁面：輸入 license key 並綁定至指定 Edge。
struct LicenseActivationView: View {
    @Environment(\.dismiss) private var dismiss

    let edgeId: String
    let edgePassword: String

    /// 從 DeviceDetailView 使用時的回呼，啟用成功後重新載入 license 資訊。
    var onActivated: (() -> Void)?
    /// 從 DashboardView 使用時注入 HomeViewModel。
    var homeVM: HomeViewModel?

    @State private var licenseKey = ""
    @State private var isLoading = false
    @State private var resultMessage: String?
    @State private var isSuccess = false
    @State private var activatedPlanName: String?
    @State private var activatedExpiresAt: String?

    // License key 格式：KEY-XXXX-XXXX-XXXX
    private static let keyPattern = "^KEY-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$"

    private var normalizedKey: String {
        licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var isKeyFormatValid: Bool {
        NSPredicate(format: "SELF MATCHES %@", Self.keyPattern).evaluate(with: normalizedKey)
    }

    private var isFormValid: Bool {
        isKeyFormatValid && !edgeId.isEmpty
    }

    init(edgeId: String, edgePassword: String, homeVM: HomeViewModel? = nil, onActivated: (() -> Void)? = nil) {
        self.edgeId = edgeId
        self.edgePassword = edgePassword
        self.homeVM = homeVM
        self.onActivated = onActivated
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.secondaryBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        headerSection
                        inputSection

                        if let resultMessage {
                            resultBanner
                        }

                        if isSuccess {
                            successDetail
                        }

                        activateButton
                        Spacer()
                    }
                    .padding(24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isSuccess ? "完成" : "取消") { dismiss() }
                }
            }
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("啟用授權金鑰")
                .font(.displaySmall)
                .foregroundColor(.textPrimary)
            Text("輸入授權金鑰以啟用裝置 \(edgeId)")
                .font(.bodyMedium)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
    }

    private var inputSection: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                AppTextField(
                    title: "KEY-XXXX-XXXX-XXXX",
                    text: $licenseKey,
                    icon: "key",
                    errorMessage: licenseKey.isEmpty ? nil : (isKeyFormatValid ? nil : "格式：KEY-XXXX-XXXX-XXXX")
                )
                .onChange(of: licenseKey) { _, newValue in
                    // Auto-format: uppercase and insert dashes
                    let cleaned = newValue.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
                    if cleaned != newValue {
                        licenseKey = cleaned
                    }
                }

                Text("請向管理員索取授權金鑰")
                    .font(.captionText)
                    .foregroundColor(.textTertiary)
                    .padding(.leading, 4)
            }

            GlassContainer(padding: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.bodyLarge)
                        .foregroundStyle(Color.primaryBrand)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("目標裝置")
                            .font(.captionText)
                            .foregroundStyle(Color.textSecondary)
                        Text(edgeId)
                            .font(.bodyMedium.monospaced().weight(.medium))
                            .foregroundStyle(Color.textPrimary)
                    }
                    Spacer()
                }
            }
        }
    }

    private var resultBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(isSuccess ? .successGreen : .errorRed)
            Text(resultMessage ?? "")
                .font(.bodySmall)
                .foregroundColor(isSuccess ? .successGreen : .errorRed)
            Spacer()
        }
        .padding(14)
        .background((isSuccess ? Color.successGreen : Color.errorRed).opacity(0.08))
        .cornerRadius(12)
    }

    private var successDetail: some View {
        GlassContainer(padding: 20) {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(Color.successGreen)
                    Text("授權啟用成功")
                        .font(.bodyLarge.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                }

                Divider().background(Color.border)

                if let planName = activatedPlanName {
                    HStack {
                        Text("方案")
                            .font(.bodyMedium)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(planName)
                            .font(.bodyMedium.weight(.medium))
                            .foregroundStyle(Color.textPrimary)
                    }
                }

                if let expiresAt = activatedExpiresAt {
                    HStack {
                        Text("到期時間")
                            .font(.bodyMedium)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(formatDate(expiresAt))
                            .font(.bodyMedium.weight(.medium))
                            .foregroundStyle(Color.textPrimary)
                    }
                }
            }
        }
    }

    private var activateButton: some View {
        PrimaryButton(
            "啟用授權",
            icon: "key.fill",
            isLoading: isLoading,
            isDisabled: !isFormValid || isSuccess
        ) {
            Task { await activate() }
        }
    }

    // MARK: - Actions

    private func activate() async {
        isLoading = true
        resultMessage = nil
        defer { isLoading = false }

        do {
            let response = try await APIClient.shared.activateLicense(
                licenseKey: normalizedKey,
                edgeId: edgeId,
                edgePassword: edgePassword
            )
            if response.errorCode.isSuccess {
                isSuccess = true
                resultMessage = "授權金鑰啟用成功"
                activatedPlanName = response.planName
                activatedExpiresAt = response.expiresAt
                onActivated?()
            } else {
                isSuccess = false
                resultMessage = response.errorCode.message
            }
        } catch {
            isSuccess = false
            resultMessage = error.localizedDescription
        }
    }

    private func formatDate(_ dateString: String) -> String {
        RedSafeDateFormatter.displayAbsolute(from: dateString)
    }
}
