import SwiftUI

// MARK: - ViewModel

@MainActor
@Observable
final class DetectionPoliciesViewModel {
    // Camera selection
    private(set) var cameras: [AddedIPCameraDTO] = []
    var selectedCameraIP: String = ""
    private(set) var isLoadingCameras = true
    private(set) var isLoadingPolicies = false
    private(set) var errorMessage: String?
    var showNoLicenseAlert = false

    // Fall detection
    var fallEnabled = false
    private(set) var isSavingFall = false
    private(set) var fallSaveResult: SaveResult?

    // Inactivity
    var inactivityEnabled = false
    var idleMinutes = 30
    var quietEnabled = false
    var quietStartDate = timeDate(hour: 22, minute: 0)
    var quietEndDate = timeDate(hour: 7, minute: 0)
    private(set) var isSavingInactivity = false
    private(set) var inactivitySaveResult: SaveResult?

    // Bed ROI
    var bedRoiEnabled = false
    var bedQuietStartDate = timeDate(hour: 22, minute: 0)
    var bedQuietEndDate = timeDate(hour: 7, minute: 0)
    var roiPoints: [BedRoiPoint] = []
    private(set) var snapshotImage: UIImage?
    private(set) var isLoadingSnapshot = false
    private(set) var isSavingBedRoi = false
    private(set) var bedRoiSaveResult: SaveResult?

    private let edgeId: String
    private var policiesCache: [String: CameraPoliciesDTO] = [:]
    private var snapshotCache: [String: UIImage] = [:]
    private var camerasLoaded = false

    init(edgeId: String) { self.edgeId = edgeId }

    // MARK: - Public

    func loadCamerasIfNeeded() async {
        guard !camerasLoaded else { return }
        isLoadingCameras = true
        errorMessage = nil
        do {
            let command = try await APIClient.shared.sendEdgeCommand(edgeId: edgeId, code: "103")
            let result: EdgeCommandResultDTO<[AddedIPCameraDTO]> =
                try await APIClient.shared.fetchEdgeCommandResult(traceId: command.traceId)
            cameras = result.result ?? []
            camerasLoaded = true
            if cameras.count == 1 {
                selectedCameraIP = cameras[0].ipAddress
            }
        } catch let error as ApiError where error.isNoValidLicense {
            showNoLicenseAlert = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingCameras = false
    }

    func onCameraSelected(_ ip: String) async {
        guard !ip.isEmpty else { return }
        if let cached = policiesCache[ip] {
            applyPolicies(cached)
            snapshotImage = snapshotCache[ip]
            clearSaveResults()
        } else {
            await fetchPolicies()
        }
    }

    func saveFallDetection() async {
        isSavingFall = true; fallSaveResult = nil
        do {
            let payload = UpdateFallPayload(ipAddress: selectedCameraIP, enabled: fallEnabled)
            let command = try await APIClient.shared.sendEdgeCommand(edgeId: edgeId, code: "302", payload: payload)
            let result: EdgeCommandResultDTO<IgnoredResult> =
                try await APIClient.shared.fetchEdgeCommandResult(traceId: command.traceId)
            if result.status.lowercased() == "ok" {
                updateCachedFall(enabled: fallEnabled); fallSaveResult = .success
            } else { fallSaveResult = .error(result.errorMessage ?? "儲存失敗") }
        } catch let error as ApiError where error.isNoValidLicense {
            showNoLicenseAlert = true
        } catch { fallSaveResult = .error(error.localizedDescription) }
        isSavingFall = false
    }

    func saveInactivity() async {
        isSavingInactivity = true; inactivitySaveResult = nil
        do {
            let payload = UpdateInactivityPayload(
                ipAddress: selectedCameraIP,
                inactivity: .init(
                    enabled: inactivityEnabled, idleMinutes: idleMinutes,
                    quietStart: Self.timeString(from: quietStartDate),
                    quietEnd: Self.timeString(from: quietEndDate),
                    quietEnabled: quietEnabled))
            let command = try await APIClient.shared.sendEdgeCommand(edgeId: edgeId, code: "303", payload: payload)
            let result: EdgeCommandResultDTO<IgnoredResult> =
                try await APIClient.shared.fetchEdgeCommandResult(traceId: command.traceId)
            if result.status.lowercased() == "ok" {
                updateCachedInactivity(); inactivitySaveResult = .success
            } else { inactivitySaveResult = .error(result.errorMessage ?? "儲存失敗") }
        } catch let error as ApiError where error.isNoValidLicense {
            showNoLicenseAlert = true
        } catch { inactivitySaveResult = .error(error.localizedDescription) }
        isSavingInactivity = false
    }

    func fetchSnapshot() async {
        isLoadingSnapshot = true
        do {
            let payload = IPAddressPayload(ipAddress: selectedCameraIP)
            let command = try await APIClient.shared.sendEdgeCommand(edgeId: edgeId, code: "305", payload: payload)
            let result: EdgeCommandResultDTO<BedSnapshotDTO> =
                try await APIClient.shared.fetchEdgeCommandResult(traceId: command.traceId)
            if let dataUrl = result.result?.dataUrl, let image = Self.decodeDataURL(dataUrl) {
                snapshotImage = image
                snapshotCache[selectedCameraIP] = image
                roiPoints = policiesCache[selectedCameraIP]?.bedRoi.points ?? []
            } else { errorMessage = result.errorMessage ?? "無法解析快照圖片" }
        } catch let error as ApiError where error.isNoValidLicense {
            showNoLicenseAlert = true
        } catch { errorMessage = "擷取快照失敗：\(error.localizedDescription)" }
        isLoadingSnapshot = false
    }

    func saveBedRoi() async {
        isSavingBedRoi = true; bedRoiSaveResult = nil
        do {
            let payload = UpdateBedRoiPayload(
                ipAddress: selectedCameraIP,
                bedRoi: .init(
                    points: roiPoints, enabled: bedRoiEnabled,
                    quietStart: Self.timeString(from: bedQuietStartDate),
                    quietEnd: Self.timeString(from: bedQuietEndDate)))
            let command = try await APIClient.shared.sendEdgeCommand(edgeId: edgeId, code: "304", payload: payload)
            let result: EdgeCommandResultDTO<IgnoredResult> =
                try await APIClient.shared.fetchEdgeCommandResult(traceId: command.traceId)
            if result.status.lowercased() == "ok" {
                updateCachedBedRoi(); bedRoiSaveResult = .success
            } else { bedRoiSaveResult = .error(result.errorMessage ?? "儲存失敗") }
        } catch let error as ApiError where error.isNoValidLicense {
            showNoLicenseAlert = true
        } catch { bedRoiSaveResult = .error(error.localizedDescription) }
        isSavingBedRoi = false
    }

    func addROIPoint(normalizedX: Double, normalizedY: Double) {
        guard roiPoints.count < 4 else { return }
        roiPoints.append(BedRoiPoint(
            x: (normalizedX * 1000).rounded() / 1000,
            y: (normalizedY * 1000).rounded() / 1000))
    }

    func clearROIPoints() { roiPoints = [] }

    var selectedCameraName: String {
        cameras.first(where: { $0.ipAddress == selectedCameraIP })
            .map { $0.customName.isEmpty ? $0.ipAddress : $0.customName } ?? ""
    }

    // MARK: - Private

    private func fetchPolicies() async {
        isLoadingPolicies = true; errorMessage = nil; clearSaveResults()
        do {
            let payload = IPAddressPayload(ipAddress: selectedCameraIP)
            let command = try await APIClient.shared.sendEdgeCommand(edgeId: edgeId, code: "301", payload: payload)
            let result: EdgeCommandResultDTO<CameraPoliciesDTO> =
                try await APIClient.shared.fetchEdgeCommandResult(traceId: command.traceId)
            if let policies = result.result {
                policiesCache[selectedCameraIP] = policies
                applyPolicies(policies)
                snapshotImage = snapshotCache[selectedCameraIP]
            } else if let msg = result.errorMessage {
                errorMessage = msg
            }
        } catch let error as ApiError where error.isNoValidLicense {
            showNoLicenseAlert = true
        } catch { errorMessage = error.localizedDescription }
        isLoadingPolicies = false
    }

    private func applyPolicies(_ p: CameraPoliciesDTO) {
        fallEnabled = p.fallDetection.enabled
        inactivityEnabled = p.inactivity.enabled
        idleMinutes = p.inactivity.idleMinutes
        quietEnabled = p.inactivity.quietEnabled
        quietStartDate = Self.parseTime(p.inactivity.quietStart)
        quietEndDate = Self.parseTime(p.inactivity.quietEnd)
        bedRoiEnabled = p.bedRoi.enabled
        bedQuietStartDate = Self.parseTime(p.bedRoi.quietStart)
        bedQuietEndDate = Self.parseTime(p.bedRoi.quietEnd)
        roiPoints = p.bedRoi.points
    }

    private func clearSaveResults() {
        fallSaveResult = nil; inactivitySaveResult = nil; bedRoiSaveResult = nil
    }

    private func updateCachedFall(enabled: Bool) {
        guard let c = policiesCache[selectedCameraIP] else { return }
        policiesCache[selectedCameraIP] = CameraPoliciesDTO(
            ipAddress: c.ipAddress, fallDetection: FallDetectionPolicy(enabled: enabled),
            inactivity: c.inactivity, bedRoi: c.bedRoi)
    }
    private func updateCachedInactivity() {
        guard let c = policiesCache[selectedCameraIP] else { return }
        policiesCache[selectedCameraIP] = CameraPoliciesDTO(
            ipAddress: c.ipAddress, fallDetection: c.fallDetection,
            inactivity: InactivityPolicy(
                enabled: inactivityEnabled, idleMinutes: idleMinutes,
                quietStart: Self.timeString(from: quietStartDate),
                quietEnd: Self.timeString(from: quietEndDate), quietEnabled: quietEnabled),
            bedRoi: c.bedRoi)
    }
    private func updateCachedBedRoi() {
        guard let c = policiesCache[selectedCameraIP] else { return }
        policiesCache[selectedCameraIP] = CameraPoliciesDTO(
            ipAddress: c.ipAddress, fallDetection: c.fallDetection, inactivity: c.inactivity,
            bedRoi: BedRoiPolicy(
                points: roiPoints, enabled: bedRoiEnabled,
                quietStart: Self.timeString(from: bedQuietStartDate),
                quietEnd: Self.timeString(from: bedQuietEndDate)))
    }

    // MARK: - Static Helpers

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        f.timeZone = TimeZone(identifier: "Asia/Taipei"); return f
    }()
    static func timeString(from date: Date) -> String { timeFormatter.string(from: date) }
    static func parseTime(_ s: String) -> Date {
        guard !s.isEmpty else { return timeDate(hour: 0, minute: 0) }
        return timeFormatter.date(from: s) ?? timeDate(hour: 0, minute: 0)
    }
    private static func decodeDataURL(_ dataUrl: String) -> UIImage? {
        let b64: String
        if let i = dataUrl.firstIndex(of: ",") { b64 = String(dataUrl[dataUrl.index(after: i)...]) }
        else { b64 = dataUrl }
        guard let data = Data(base64Encoded: b64) else { return nil }
        return UIImage(data: data)
    }
}

private func timeDate(hour: Int, minute: Int) -> Date {
    var c = DateComponents(); c.hour = hour; c.minute = minute
    return Calendar.current.date(from: c) ?? Date()
}

enum SaveResult {
    case success, error(String)
    var isSuccess: Bool { if case .success = self { return true }; return false }
}

// MARK: - Main View

struct DetectionPoliciesView: View {
    let edge: EdgeSummary
    @State private var viewModel: DetectionPoliciesViewModel

    init(edge: EdgeSummary) {
        self.edge = edge
        _viewModel = State(initialValue: DetectionPoliciesViewModel(edgeId: edge.edgeId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                pageHeader
                cameraSelector

                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error)
                }

                if viewModel.selectedCameraIP.isEmpty {
                    emptyState
                } else if viewModel.isLoadingPolicies {
                    LoadingCard(message: "正在載入偵測策略...")
                } else {
                    policyCards
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .background(Color.appBackground)
        .navigationTitle("偵測策略")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .offlineOverlay(isOnline: edge.isOnline)
        .task { await viewModel.loadCamerasIfNeeded() }
        .onChange(of: viewModel.selectedCameraIP) { _, newValue in
            Task { await viewModel.onCameraSelected(newValue) }
        }
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

    // MARK: - Page Header

    private var pageHeader: some View {
        GlassContainer(padding: 0) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.primaryBrand.opacity(0.1))
                        .frame(width: 56, height: 56)
                    Image(systemName: "shield.checkered")
                        .font(.title2)
                        .foregroundStyle(Color.primaryBrand)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("偵測策略管理")
                        .font(.bodyLarge.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("配置跌倒、靜止與離床偵測規則")
                        .font(.captionText)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
            }
            .padding(20)
        }
    }

    // MARK: - Camera Selector (horizontal chips)

    private var cameraSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("攝影機")
                .font(.bodyLarge.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 4)

            if viewModel.isLoadingCameras {
                GlassContainer(padding: 20) {
                    HStack {
                        Spacer()
                        ProgressView().tint(.primaryBrand)
                        Text("正在載入攝影機...")
                            .font(.bodyMedium)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                    }
                }
            } else if viewModel.cameras.isEmpty {
                GlassContainer(padding: 20) {
                    HStack(spacing: 12) {
                        Image(systemName: "camera.badge.ellipsis")
                            .font(.title3)
                            .foregroundStyle(Color.textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("尚無攝影機")
                                .font(.bodyMedium.weight(.medium))
                                .foregroundStyle(Color.textPrimary)
                            Text("請先至 IP Camera 配置新增攝影機")
                                .font(.captionText)
                                .foregroundStyle(Color.textTertiary)
                        }
                        Spacer()
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.cameras) { cam in
                            CameraChip(
                                name: cam.customName.isEmpty ? cam.ipcName : cam.customName,
                                ip: cam.ipAddress,
                                isSelected: viewModel.selectedCameraIP == cam.ipAddress
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.selectedCameraIP = cam.ipAddress
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 20)

            ZStack {
                Circle()
                    .fill(Color.primaryBrand.opacity(0.06))
                    .frame(width: 100, height: 100)
                Image(systemName: "hand.tap")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.primaryBrand.opacity(0.4))
            }

            VStack(spacing: 8) {
                Text("選擇攝影機")
                    .font(.bodyLarge.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("點選上方攝影機以查看並配置偵測策略")
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.center)
            }

            // Preview cards (disabled)
            VStack(spacing: 12) {
                PolicyPreviewRow(icon: "figure.fall", title: "跌倒偵測", subtitle: "偵測人員跌倒並即時通知")
                PolicyPreviewRow(icon: "figure.stand", title: "靜止偵測", subtitle: "偵測人員長時間未移動")
                PolicyPreviewRow(icon: "bed.double.fill", title: "離床偵測", subtitle: "監測夜間離床事件與區域")
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Policy Cards

    private var policyCards: some View {
        VStack(spacing: 16) {
            // Selected camera indicator
            HStack(spacing: 8) {
                Image(systemName: "video.fill")
                    .font(.caption)
                    .foregroundStyle(Color.primaryBrand)
                Text(viewModel.selectedCameraName)
                    .font(.captionText.weight(.medium))
                    .foregroundStyle(Color.primaryBrand)
                Spacer()
            }
            .padding(.horizontal, 4)

            FallDetectionSection(viewModel: viewModel)
            InactivitySection(viewModel: viewModel)
            BedRoiSection(viewModel: viewModel)
        }
    }
}

// MARK: - Camera Chip

private struct CameraChip: View {
    let name: String
    let ip: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.primaryBrand : Color.primaryBrand.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: "video.fill")
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white : Color.primaryBrand)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? ip : name)
                        .font(.captionText.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
                        .lineLimit(1)
                    Text(ip)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.primaryBrand.opacity(0.08) : Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.primaryBrand : Color.border, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Policy Preview Row (disabled state)

private struct PolicyPreviewRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        GlassContainer(padding: 16) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.textTertiary.opacity(0.08))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textTertiary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.bodyMedium.weight(.medium))
                        .foregroundStyle(Color.textTertiary)
                    Text(subtitle)
                        .font(.captionText)
                        .foregroundStyle(Color.textTertiary.opacity(0.6))
                }
                Spacer()

                Text("--")
                    .font(.captionText.weight(.medium))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.surface)
                    .clipShape(Capsule())
            }
        }
        .opacity(0.6)
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let enabled: Bool

    var body: some View {
        Text(enabled ? "啟用" : "停用")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(enabled ? Color.successGreen : Color.textTertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(enabled ? Color.successGreen.opacity(0.12) : Color.surface)
            )
    }
}

// MARK: - Fall Detection Section

private struct FallDetectionSection: View {
    @Bindable var viewModel: DetectionPoliciesViewModel

    var body: some View {
        GlassContainer(padding: 20) {
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primaryBrand.opacity(0.1))
                            .frame(width: 40, height: 40)
                        Image(systemName: "figure.fall")
                            .font(.bodyMedium)
                            .foregroundStyle(Color.primaryBrand)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("跌倒偵測")
                            .font(.bodyMedium.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("偵測人員跌倒並即時通知")
                            .font(.captionText)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()

                    Toggle("", isOn: $viewModel.fallEnabled)
                        .labelsHidden()
                        .tint(.primaryBrand)
                }

                SaveResultBanner(result: viewModel.fallSaveResult)

                PrimaryButton("儲存", isLoading: viewModel.isSavingFall, isDisabled: false) {
                    Task { await viewModel.saveFallDetection() }
                }
            }
        }
    }
}

// MARK: - Inactivity Section

private struct InactivitySection: View {
    @Bindable var viewModel: DetectionPoliciesViewModel

    var body: some View {
        GlassContainer(padding: 20) {
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primaryBrand.opacity(0.1))
                            .frame(width: 40, height: 40)
                        Image(systemName: "figure.stand")
                            .font(.bodyMedium)
                            .foregroundStyle(Color.primaryBrand)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("靜止偵測")
                            .font(.bodyMedium.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("偵測人員長時間未移動")
                            .font(.captionText)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()

                    Toggle("", isOn: $viewModel.inactivityEnabled)
                        .labelsHidden()
                        .tint(.primaryBrand)
                }

                if viewModel.inactivityEnabled {
                    Divider().background(Color.border)

                    Stepper(value: $viewModel.idleMinutes, in: 1...120) {
                        HStack(spacing: 10) {
                            Image(systemName: "clock")
                                .font(.captionText)
                                .foregroundStyle(Color.textSecondary)
                                .frame(width: 20)
                            Text("閾值")
                                .font(.bodyMedium)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text("\(viewModel.idleMinutes) 分鐘")
                                .font(.bodyMedium.weight(.medium))
                                .foregroundStyle(Color.primaryBrand)
                        }
                    }

                    Divider().background(Color.border)

                    HStack {
                        HStack(spacing: 10) {
                            Image(systemName: "moon.fill")
                                .font(.captionText)
                                .foregroundStyle(Color.textSecondary)
                                .frame(width: 20)
                            Text("免打擾")
                                .font(.bodyMedium)
                                .foregroundStyle(Color.textPrimary)
                        }
                        Spacer()
                        Toggle("", isOn: $viewModel.quietEnabled)
                            .labelsHidden()
                            .tint(.primaryBrand)
                    }

                    if viewModel.quietEnabled {
                        TimeRangeRow(
                            startLabel: "開始", endLabel: "結束",
                            startDate: $viewModel.quietStartDate,
                            endDate: $viewModel.quietEndDate)
                    }
                }

                SaveResultBanner(result: viewModel.inactivitySaveResult)

                PrimaryButton("儲存", isLoading: viewModel.isSavingInactivity, isDisabled: false) {
                    Task { await viewModel.saveInactivity() }
                }
            }
        }
    }
}

// MARK: - Bed ROI Section

private struct BedRoiSection: View {
    @Bindable var viewModel: DetectionPoliciesViewModel

    var body: some View {
        GlassContainer(padding: 20) {
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primaryBrand.opacity(0.1))
                            .frame(width: 40, height: 40)
                        Image(systemName: "bed.double.fill")
                            .font(.bodyMedium)
                            .foregroundStyle(Color.primaryBrand)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("離床偵測")
                            .font(.bodyMedium.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("監測夜間離床事件與 ROI 區域")
                            .font(.captionText)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()

                    Toggle("", isOn: $viewModel.bedRoiEnabled)
                        .labelsHidden()
                        .tint(.primaryBrand)
                }

                if viewModel.bedRoiEnabled {
                    Divider().background(Color.border)

                    TimeRangeRow(
                        startLabel: "偵測開始", endLabel: "偵測結束",
                        startDate: $viewModel.bedQuietStartDate,
                        endDate: $viewModel.bedQuietEndDate)

                    Divider().background(Color.border)

                    SnapshotROIView(viewModel: viewModel)
                }

                SaveResultBanner(result: viewModel.bedRoiSaveResult)

                PrimaryButton("儲存", isLoading: viewModel.isSavingBedRoi, isDisabled: false) {
                    Task { await viewModel.saveBedRoi() }
                }
            }
        }
    }
}

// MARK: - Snapshot + ROI

private struct SnapshotROIView: View {
    @Bindable var viewModel: DetectionPoliciesViewModel

    var body: some View {
        VStack(spacing: 12) {
            Button {
                Task { await viewModel.fetchSnapshot() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isLoadingSnapshot {
                        ProgressView().scaleEffect(0.8).tint(.primaryBrand)
                    } else {
                        Image(systemName: "camera.viewfinder")
                            .font(.bodyMedium)
                    }
                    Text(viewModel.isLoadingSnapshot ? "擷取中..." : "擷取快照")
                        .font(.bodyMedium.weight(.semibold))
                }
                .foregroundStyle(Color.primaryBrand)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.primaryBrand.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoadingSnapshot)

            if let image = viewModel.snapshotImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        GeometryReader { geo in
                            ROIOverlay(points: viewModel.roiPoints, size: geo.size)
                        }
                    }
                    .overlay {
                        GeometryReader { geo in
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { location in
                                    viewModel.addROIPoint(
                                        normalizedX: max(0, min(1, location.x / geo.size.width)),
                                        normalizedY: max(0, min(1, location.y / geo.size.height)))
                                }
                        }
                    }

                HStack {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                    Text("點選圖片設定 ROI 頂點（最多 4 個）")
                        .font(.captionText)
                }
                .foregroundStyle(Color.textTertiary)
            }

            if !viewModel.roiPoints.isEmpty {
                HStack {
                    HStack(spacing: 4) {
                        ForEach(0..<4) { i in
                            Circle()
                                .fill(i < viewModel.roiPoints.count ? Color.primaryBrand : Color.border)
                                .frame(width: 8, height: 8)
                        }
                    }
                    Text("\(viewModel.roiPoints.count)/4 頂點")
                        .font(.captionText)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Button { viewModel.clearROIPoints() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.caption2)
                            Text("清除")
                                .font(.captionText.weight(.semibold))
                        }
                        .foregroundStyle(Color.errorRed)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.errorRed.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ROIOverlay: View {
    let points: [BedRoiPoint]
    let size: CGSize

    var body: some View {
        ZStack {
            if points.count >= 2 {
                roiPath.fill(Color.primaryBrand.opacity(0.15))
                roiPath.stroke(Color.primaryBrand, lineWidth: 2)
            }
            ForEach(points.indices, id: \.self) { i in
                Circle()
                    .fill(Color.primaryBrand)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .position(x: points[i].x * size.width, y: points[i].y * size.height)
            }
        }
    }

    private var roiPath: Path {
        Path { path in
            for (i, p) in points.enumerated() {
                let pt = CGPoint(x: p.x * size.width, y: p.y * size.height)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            if points.count >= 3 { path.closeSubpath() }
        }
    }
}

// MARK: - Shared Components

private struct TimeRangeRow: View {
    let startLabel: String
    let endLabel: String
    @Binding var startDate: Date
    @Binding var endDate: Date

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(startLabel)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                DatePicker("", selection: $startDate, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            HStack {
                Text(endLabel)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                DatePicker("", selection: $endDate, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
        }
    }
}

private struct SaveResultBanner: View {
    let result: SaveResult?

    var body: some View {
        if let result {
            HStack(spacing: 8) {
                Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                Text(result.isSuccess ? "儲存成功" : errorMsg)
                    .font(.captionText)
            }
            .foregroundStyle(result.isSuccess ? Color.successGreen : Color.errorRed)
        }
    }

    private var errorMsg: String {
        if case .error(let m) = result { return m }
        return ""
    }
}

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
                Text(message).font(.bodyMedium).foregroundStyle(Color.textSecondary)
                Spacer()
            }
        }
    }
}
