import SwiftUI

// MARK: - ViewModel

@MainActor
@Observable
final class GeminiConfigViewModel {
    var geminiEnabled = false
    var apiKey = ""
    var selectedModel = "gemini-2.0-flash"

    private(set) var isLoading = true
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var saveResult: SaveResult?
    var showNoLicenseAlert = false

    private let edgeId: String
    private var loaded = false

    static let availableModels = [
        "gemini-2.5-flash",
        "gemini-2.5-pro",
        "gemini-2.0-flash",
        "gemini-2.0-flash-lite",
        "gemini-1.5-flash",
        "gemini-1.5-pro"
    ]

    init(edgeId: String) {
        self.edgeId = edgeId
    }

    func loadIfNeeded() async {
        guard !loaded else { return }
        isLoading = true
        errorMessage = nil
        do {
            let command = try await APIClient.shared.sendEdgeCommand(edgeId: edgeId, code: "306")
            let result: EdgeCommandResultDTO<GeminiConfigDTO> =
                try await APIClient.shared.fetchEdgeCommandResult(traceId: command.traceId)
            if let config = result.result {
                geminiEnabled = config.gemini.enabled
                apiKey = config.gemini.apiKey
                selectedModel = config.gemini.model
            } else if let msg = result.errorMessage {
                errorMessage = msg
            }
            loaded = true
        } catch let error as ApiError where error.isNoValidLicense {
            showNoLicenseAlert = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func save() async {
        isSaving = true
        saveResult = nil
        do {
            let payload = UpdateGeminiPayload(
                enabled: geminiEnabled,
                apiKey: apiKey,
                model: selectedModel
            )
            let command = try await APIClient.shared.sendEdgeCommand(edgeId: edgeId, code: "307", payload: payload)
            let result: EdgeCommandResultDTO<IgnoredResult> =
                try await APIClient.shared.fetchEdgeCommandResult(traceId: command.traceId)
            saveResult = result.status.lowercased() == "ok" ? .success : .error(result.errorMessage ?? "儲存失敗")
        } catch let error as ApiError where error.isNoValidLicense {
            showNoLicenseAlert = true
        } catch {
            saveResult = .error(error.localizedDescription)
        }
        isSaving = false
    }
}

// MARK: - View

struct GeminiConfigView: View {
    let edge: EdgeSummary
    @State private var viewModel: GeminiConfigViewModel

    init(edge: EdgeSummary) {
        self.edge = edge
        _viewModel = State(initialValue: GeminiConfigViewModel(edgeId: edge.edgeId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                headerSection

                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error)
                }

                if viewModel.isLoading {
                    LoadingCard(message: "正在載入設定...")
                } else {
                    configSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 32)
        }
        .background(Color.appBackground)
        .navigationTitle("AI 輔助偵測")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .offlineOverlay(isOnline: edge.isOnline)
        .task { await viewModel.loadIfNeeded() }
        .alert("無法執行指令", isPresented: $viewModel.showNoLicenseAlert) {
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

    private var headerSection: some View {
        GlassContainer(padding: 20) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.primaryBrand.opacity(0.1))
                        .frame(width: 56, height: 56)
                    Image(systemName: "brain.head.profile")
                        .font(.title2)
                        .foregroundStyle(Color.primaryBrand)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Gemini AI")
                        .font(.bodyLarge.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("使用 Google Gemini 分析跌倒與異常事件")
                        .font(.captionText)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()
            }
        }
    }

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("設定")
                .font(.bodyLarge.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 4)

            GlassContainer(padding: 20) {
                VStack(spacing: 16) {
                    Toggle(isOn: $viewModel.geminiEnabled) {
                        HStack(spacing: 12) {
                            Image(systemName: "power")
                                .font(.bodyLarge)
                                .foregroundStyle(Color.primaryBrand)
                                .frame(width: 24)
                            Text("啟用 Gemini AI")
                                .font(.bodyMedium)
                                .foregroundStyle(Color.textPrimary)
                        }
                    }
                    .tint(.primaryBrand)

                    Divider().background(Color.border)

                    AppTextField(
                        title: "Gemini API Key",
                        text: $viewModel.apiKey,
                        icon: "key.fill",
                        isSecure: true
                    )

                    Divider().background(Color.border)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("模型")
                            .font(.captionText.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)

                        Picker("模型", selection: $viewModel.selectedModel) {
                            ForEach(GeminiConfigViewModel.availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.primaryBrand)
                    }

                    SaveResultBanner(result: viewModel.saveResult)

                    PrimaryButton("儲存", isLoading: viewModel.isSaving, isDisabled: false) {
                        Task { await viewModel.save() }
                    }
                }
            }
        }
    }
}

// MARK: - File-Private Components

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        GlassContainer(padding: 16) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.warningOrange)
                Text(message)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
            }
        }
    }
}

private struct LoadingCard: View {
    let message: String

    var body: some View {
        GlassContainer(padding: 24) {
            HStack {
                Spacer()
                ProgressView().tint(.primaryBrand)
                Text(message)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
            }
        }
    }
}

private struct SaveResultBanner: View {
    let result: SaveResult?

    var body: some View {
        if let result {
            HStack(spacing: 8) {
                Image(systemName: result.isSuccess
                      ? "checkmark.circle.fill"
                      : "exclamationmark.triangle.fill")
                Text(message)
                    .font(.captionText)
            }
            .foregroundStyle(result.isSuccess ? Color.successGreen : Color.errorRed)
        }
    }

    private var message: String {
        guard let result else { return "" }
        switch result {
        case .success: return "儲存成功"
        case .error(let msg): return msg
        }
    }
}
