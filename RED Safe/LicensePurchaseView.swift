import SwiftUI

/// 授權方案購買頁面：顯示可用方案並支援購買流程。
struct LicensePurchaseView: View {
    @State private var plans: [PlanSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var purchaseResult: PurchaseResult?
    @State private var isPurchasing = false
    @State private var purchasingPlanId: String?

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    headerSection

                    if let result = purchaseResult {
                        purchaseSuccessCard(result: result)
                    }

                    contentSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .navigationTitle("購買授權")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadPlans()
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("選擇授權方案")
                .font(.displaySmall)
                .foregroundStyle(Color.textPrimary)
            Text("購買後可取得授權金鑰，啟用於指定 Edge 裝置。")
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)

            Button {
                if let url = URL(string: "https://introducing.redsafe-tw.com/pricing") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "safari")
                        .font(.caption)
                    Text("在瀏覽器中查看完整方案介紹")
                        .font(.captionText)
                }
                .foregroundStyle(Color.primaryBrand)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var contentSection: some View {
        Group {
            if isLoading && plans.isEmpty {
                loadingView
            } else if let errorMessage {
                errorView(message: errorMessage)
            } else if plans.isEmpty {
                emptyView
            } else {
                planList
            }
        }
    }

    private var loadingView: some View {
        GlassContainer(padding: 24) {
            HStack {
                Spacer()
                ProgressView()
                    .tint(.primaryBrand)
                Text("正在載入方案...")
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
            }
        }
    }

    private func errorView(message: String) -> some View {
        GlassContainer(padding: 20) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.warningOrange)
                    Text(message)
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textPrimary)
                }

                SecondaryButton("重新載入", icon: "arrow.clockwise") {
                    Task { await loadPlans() }
                }
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 18) {
            Image(systemName: "tag.slash")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
                .padding(.top, 40)
            Text("目前沒有可用的方案")
                .font(.title3)
                .foregroundStyle(Color.textPrimary)
            Text("請稍後再試或前往官方網站查看。")
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var planList: some View {
        LazyVStack(spacing: 16) {
            ForEach(plans) { plan in
                PlanCard(
                    plan: plan,
                    isPurchasing: purchasingPlanId == plan.planId,
                    onPurchase: { Task { await purchase(plan: plan) } }
                )
            }
        }
    }

    private func purchaseSuccessCard(result: PurchaseResult) -> some View {
        GlassContainer(padding: 20) {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(Color.successGreen)
                    Text("購買成功")
                        .font(.bodyLarge.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Button {
                        purchaseResult = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                Divider().background(Color.border)

                HStack {
                    Text("授權金鑰")
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(result.licenseKey)
                        .font(.bodyMedium.monospaced().weight(.semibold))
                        .foregroundStyle(Color.primaryBrand)
                }

                if let planName = result.planName {
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

                Button {
                    UIPasteboard.general.string = result.licenseKey
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.doc")
                        Text("複製金鑰")
                    }
                    .font(.bodyMedium.weight(.medium))
                    .foregroundStyle(Color.primaryBrand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.primaryBrand.opacity(0.1))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)

                Text("請前往裝置詳情頁面啟用此授權金鑰。")
                    .font(.captionText)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    // MARK: - Data

    private func loadPlans() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await APIClient.shared.fetchPlans()
            plans = response.plans
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func purchase(plan: PlanSummary) async {
        isPurchasing = true
        purchasingPlanId = plan.planId
        defer {
            isPurchasing = false
            purchasingPlanId = nil
        }

        do {
            let response = try await APIClient.shared.purchaseLicense(planId: plan.planId)
            if response.errorCode.isSuccess, let key = response.licenseKey {
                purchaseResult = PurchaseResult(
                    licenseKey: key,
                    planName: response.planName,
                    expiresAt: response.expiresAt
                )
            } else {
                errorMessage = response.errorCode.message
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Models

private struct PurchaseResult {
    let licenseKey: String
    let planName: String?
    let expiresAt: String?
}

// MARK: - Plan Card

private struct PlanCard: View {
    let plan: PlanSummary
    let isPurchasing: Bool
    let onPurchase: () -> Void

    var body: some View {
        GlassContainer(padding: 20) {
            VStack(spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plan.planName)
                            .font(.bodyLarge.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                        Text("\(plan.durationDays) 天")
                            .font(.captionText)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formattedPrice)
                            .font(.displaySmall)
                            .foregroundStyle(Color.primaryBrand)
                        Text(plan.currency)
                            .font(.captionText)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Divider().background(Color.border)

                // Features
                HStack(spacing: 16) {
                    featureTag(icon: "camera", text: "最多 \(plan.maxCameras) 台攝影機")
                    featureTag(icon: "calendar", text: "\(plan.durationDays) 天效期")
                    Spacer()
                }

                // Purchase Button
                PrimaryButton(
                    "購買此方案",
                    icon: "cart.fill",
                    isLoading: isPurchasing,
                    isDisabled: isPurchasing
                ) {
                    onPurchase()
                }
            }
        }
    }

    private var formattedPrice: String {
        if let value = Double(plan.price), value == floor(value) {
            return String(format: "%.0f", value)
        }
        return plan.price
    }

    private func featureTag(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.primaryBrand)
            Text(text)
                .font(.captionText)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primaryBrand.opacity(0.06))
        .cornerRadius(8)
    }
}
