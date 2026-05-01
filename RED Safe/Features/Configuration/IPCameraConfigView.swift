import SwiftUI

struct IPCameraConfigView: View {
    let edge: EdgeSummary

    // 資料
    @State private var scanResults: [IPCameraDeviceDTO] = []
    @State private var addedDevices: [AddedIPCameraDTO] = []

    // Loading 狀態
    @State private var isScanning = false
    @State private var isFetchingAdded = false
    @State private var isSubmittingAdd = false
    @State private var isSubmittingEdit = false
    @State private var deletingIP: String?

    // 錯誤
    @State private var scanError: String?
    @State private var addedError: String?

    // Modals
    @State private var addSheet: AddSheetContext?
    @State private var editSheet: EditSheetContext?
    @State private var addFormError: String?
    @State private var editFormError: String?
    @State private var pendingRemove: AddedIPCameraDTO?

    // 提示
    @State private var infoAlert: InfoAlert?
    @State private var showNoLicenseAlert = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                actionHeader

                if let scanError {
                    inlineError(scanError)
                }

                boundSection

                scanSection
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background(Color.appBackground)
        .navigationTitle("IP Camera 配置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .offlineOverlay(isOnline: edge.isOnline)
        .refreshable { await refreshAll() }
        .task(id: edge.edgeId) {
            await fetchAddedCameras(silent: false)
        }
        .sheet(item: $addSheet, onDismiss: { addFormError = nil }) { ctx in
            AddCameraSheet(
                context: ctx,
                error: $addFormError,
                isSubmitting: isSubmittingAdd,
                onSubmit: { input in Task { await submitAdd(context: ctx, input: input) } }
            )
        }
        .sheet(item: $editSheet, onDismiss: { editFormError = nil }) { ctx in
            EditCameraSheet(
                context: ctx,
                error: $editFormError,
                isSubmitting: isSubmittingEdit,
                onSubmit: { input in Task { await submitEdit(context: ctx, input: input) } }
            )
        }
        .alert(item: $infoAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("好"))
            )
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
        .alert(
            "解除綁定",
            isPresented: Binding(
                get: { pendingRemove != nil },
                set: { if !$0 { pendingRemove = nil } }
            ),
            presenting: pendingRemove
        ) { device in
            Button("解除綁定", role: .destructive) {
                Task { await removeCamera(device) }
            }
            Button("取消", role: .cancel) {}
        } message: { device in
            Text("確認要解除攝影機「\(displayName(for: device))」的綁定嗎？\n關聯的偵測策略也會一併移除。")
        }
    }

    // MARK: - Sections

    private var actionHeader: some View {
        GlassContainer(padding: 0) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.primaryBrand.opacity(0.1))
                        .frame(width: 56, height: 56)
                    Image(systemName: isScanning ? "rays" : "dot.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundColor(.primaryBrand)
                        .symbolEffect(.variableColor.iterative.reversing, isActive: isScanning)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("攝影機管理")
                        .font(.bodyLarge.weight(.semibold))
                        .foregroundColor(.textPrimary)
                    Text(isScanning ? "正在掃描周邊攝影機…" : "搜尋、綁定、編輯、解除")
                        .font(.captionText)
                        .foregroundColor(.textSecondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    headerIconButton(systemImage: "plus", accessibilityLabel: "手動新增") {
                        addSheet = .manual
                    }
                    headerIconButton(
                        systemImage: "magnifyingglass",
                        accessibilityLabel: isScanning ? "掃描中" : "搜尋裝置",
                        isPrimary: true,
                        isLoading: isScanning
                    ) {
                        Task { await triggerScan() }
                    }
                }
            }
            .padding(20)
        }
    }

    private var boundSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "已綁定攝影機", count: addedDevices.count, accent: .successGreen)

            if let addedError {
                inlineError(addedError)
            }

            if isFetchingAdded && addedDevices.isEmpty {
                GlassContainer(padding: 24) {
                    HStack {
                        ProgressView()
                        Text("正在載入…")
                            .font(.bodyMedium)
                            .foregroundColor(.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else if addedDevices.isEmpty {
                GlassContainer(padding: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash")
                            .font(.title2)
                            .foregroundColor(.textTertiary)
                        Text("尚未綁定任何攝影機")
                            .font(.bodyMedium.weight(.semibold))
                            .foregroundColor(.textPrimary)
                        Text("先「搜尋裝置」找到周邊攝影機，再進行綁定。")
                            .font(.captionText)
                            .foregroundColor(.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(addedDevices) { device in
                        BoundDeviceRow(
                            displayName: displayName(for: device),
                            subtitle: device.ipcName.isEmpty ? nil : device.ipcName,
                            ipAddress: device.ipAddress,
                            macAddress: device.macAddress,
                            isDeleting: isDeleting(device),
                            onEdit: { editSheet = .init(device: device) },
                            onRemove: { pendingRemove = device }
                        )
                    }
                }
            }
        }
    }

    private var scanSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "搜尋結果", count: scanResults.count, accent: .primaryBrand)

            if isScanning {
                GlassContainer(padding: 24) {
                    HStack {
                        ProgressView()
                        Text("正在掃描周邊攝影機…")
                            .font(.bodyMedium)
                            .foregroundColor(.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else if scanResults.isEmpty {
                GlassContainer(padding: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title3)
                            .foregroundColor(.textTertiary)
                        Text("尚未搜尋到任何裝置")
                            .font(.bodyMedium)
                            .foregroundColor(.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(sortedScanResults) { device in
                        ScannedDeviceRow(
                            device: device,
                            displayName: scanDisplayName(for: device),
                            isAdded: isDeviceAlreadyAdded(device),
                            onAdd: { addSheet = .scan(device: device) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - 元件 helpers

    private func sectionHeader(title: String, count: Int, accent: Color) -> some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(accent.opacity(0.18))
                .overlay(Circle().fill(accent).frame(width: 6, height: 6))
                .frame(width: 14, height: 14)
            Text(title)
                .font(.bodyLarge.weight(.semibold))
                .foregroundColor(.textSecondary)
            Text("\(count)")
                .font(.captionText.monospaced().weight(.semibold))
                .foregroundColor(.textTertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.surface))
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func headerIconButton(
        systemImage: String,
        accessibilityLabel: String,
        isPrimary: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Image(systemName: systemImage).font(.body.weight(.semibold))
                }
            }
            .foregroundColor(isPrimary ? .white : .primaryBrand)
            .frame(width: 36, height: 36)
            .background(
                Circle().fill(isPrimary ? Color.primaryBrand : Color.primaryBrand.opacity(0.1))
            )
        }
        .disabled(isLoading)
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func inlineError(_ message: String) -> some View {
        GlassContainer(padding: 16) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.warningOrange)
                Text(message).font(.bodyMedium).foregroundColor(.textPrimary)
                Spacer()
            }
        }
    }

    // MARK: - 排序 / 顯示規則

    /// 搜尋結果排序：以 IP 由小到大（0-9）。IPv4 轉 32-bit 整數，
    /// 確保 "192.168.1.10" 排在 "192.168.1.2" 之後而不是字典序之前；
    /// 非 IPv4 退回 localizedStandardCompare 自然排序維持穩定。
    private var sortedScanResults: [IPCameraDeviceDTO] {
        scanResults.sorted { lhs, rhs in
            let lk = ipSortKey(lhs.ip)
            let rk = ipSortKey(rhs.ip)
            if lk != rk { return lk < rk }
            return lhs.ip.localizedStandardCompare(rhs.ip) == .orderedAscending
        }
    }

    private func ipSortKey(_ ip: String) -> UInt64 {
        let parts = ip.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard parts.count == 4 else { return UInt64.max }
        var acc: UInt64 = 0
        for part in parts {
            guard let n = UInt64(part), n <= 255 else { return UInt64.max }
            acc = acc * 256 + n
        }
        return acc
    }

    /// 已綁定攝影機顯示規則 — 對齊 Core resolveBoundName：customName 為主，否則「未命名攝影機」。
    private func displayName(for device: AddedIPCameraDTO) -> String {
        let trimmed = device.customName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名攝影機" : trimmed
    }

    /// 搜尋結果顯示規則 — 對齊 Core resolveDisplayName：name 為主，否則 fallback。
    private func scanDisplayName(for device: IPCameraDeviceDTO) -> String {
        let trimmed = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名攝影機" : trimmed
    }

    private func isDeviceAlreadyAdded(_ device: IPCameraDeviceDTO) -> Bool {
        let key = normalizeIPAddress(device.ip)
        guard !key.isEmpty else { return false }
        return addedDevices.contains { normalizeIPAddress($0.ipAddress) == key }
    }

    private func isDeleting(_ device: AddedIPCameraDTO) -> Bool {
        guard let deletingIP else { return false }
        return normalizeIPAddress(device.ipAddress) == deletingIP
    }

    private func normalizeIPAddress(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - 動作

    private func refreshAll() async {
        await fetchAddedCameras(silent: true)
        await triggerScan()
    }

    private func triggerScan() async {
        await MainActor.run { isScanning = true; scanError = nil }
        do {
            let command = try await APIClient.shared.sendEdgeCommand(edgeId: edge.edgeId, code: "101")
            let result: EdgeCommandResultDTO<[IPCameraDeviceDTO]> = try await APIClient.shared.fetchEdgeCommandResult(traceId: command.traceId)
            await MainActor.run {
                self.scanResults = result.result ?? []
                self.isScanning = false
                if result.result == nil, let msg = result.errorMessage {
                    self.scanError = msg
                }
            }
        } catch let error as ApiError where error.isNoValidLicense {
            await MainActor.run {
                self.isScanning = false
                self.scanError = "此裝置尚無有效授權"
                self.showNoLicenseAlert = true
            }
        } catch {
            await MainActor.run {
                self.scanResults = []
                self.isScanning = false
                self.scanError = error.localizedDescription
            }
        }
    }

    private func fetchAddedCameras(silent: Bool) async {
        await MainActor.run {
            isFetchingAdded = true
            if !silent { addedError = nil }
        }
        do {
            let command = try await APIClient.shared.sendEdgeCommand(edgeId: edge.edgeId, code: "103")
            let result: EdgeCommandResultDTO<[AddedIPCameraDTO]> = try await APIClient.shared.fetchEdgeCommandResult(traceId: command.traceId)
            await MainActor.run {
                self.addedDevices = result.result ?? []
                self.isFetchingAdded = false
            }
        } catch let error as ApiError where error.isNoValidLicense {
            await MainActor.run {
                self.isFetchingAdded = false
                self.addedError = "此裝置尚無有效授權"
                self.showNoLicenseAlert = true
            }
        } catch {
            await MainActor.run {
                self.isFetchingAdded = false
                if !silent { self.addedError = error.localizedDescription }
            }
        }
    }

    private func submitAdd(context: AddSheetContext, input: AddCameraInput) async {
        let trimmedIP = input.ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIP.isEmpty else {
            await MainActor.run { addFormError = "請輸入 IP 位址" }
            return
        }
        // 對齊 Core：先攔截重複 IP，提早提示體驗更好
        if addedDevices.contains(where: { normalizeIPAddress($0.ipAddress) == normalizeIPAddress(trimmedIP) }) {
            await MainActor.run {
                addSheet = nil
                infoAlert = .init(title: "此攝影機已綁定", message: "IP \(trimmedIP) 已存在於已綁定清單。")
            }
            return
        }

        let trimmedCustom = input.customName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName: String
        switch context {
        case .manual:
            fallbackName = trimmedCustom.isEmpty ? trimmedIP : trimmedCustom
        case .scan(let device):
            fallbackName = trimmedCustom.isEmpty ? device.name : trimmedCustom
        }

        let payload = AddIPCameraCommandPayload(
            ipAddress: trimmedIP,
            macAddress: macForContext(context),
            ipcName: ipcNameForContext(context, fallback: fallbackName),
            customName: fallbackName,
            ipcAccount: input.account.trimmingCharacters(in: .whitespacesAndNewlines),
            ipcPassword: input.password
        )

        await MainActor.run { isSubmittingAdd = true; addFormError = nil }
        do {
            let command = try await APIClient.shared.sendEdgeCommand(edgeId: edge.edgeId, code: "104", payload: payload)
            let result: EdgeCommandResultDTO<AddIPCameraResultDTO> = try await APIClient.shared.fetchEdgeCommandResult(traceId: command.traceId)

            let trimmedError = result.result?.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.status.lowercased() == "ok", (trimmedError?.isEmpty ?? true) {
                await MainActor.run {
                    isSubmittingAdd = false
                    addSheet = nil
                    infoAlert = .init(title: "綁定成功", message: "攝影機已成功新增。")
                }
                await fetchAddedCameras(silent: true)
            } else {
                let message = trimmedError?.isEmpty == false ? trimmedError! : (result.errorMessage ?? "新增失敗，請稍後再試。")
                if isAlreadyBoundError(message) {
                    await MainActor.run {
                        isSubmittingAdd = false
                        addSheet = nil
                        infoAlert = .init(title: "此攝影機已綁定", message: message)
                    }
                    await fetchAddedCameras(silent: true)
                } else {
                    await MainActor.run {
                        isSubmittingAdd = false
                        addFormError = message
                    }
                }
            }
        } catch let error as ApiError where error.isNoValidLicense {
            await MainActor.run {
                isSubmittingAdd = false
                addSheet = nil
                showNoLicenseAlert = true
            }
        } catch {
            await MainActor.run {
                isSubmittingAdd = false
                addFormError = error.localizedDescription
            }
        }
    }

    private func submitEdit(context: EditSheetContext, input: EditCameraInput) async {
        let trimmedCustom = input.customName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCustom.isEmpty else {
            await MainActor.run { editFormError = "請輸入自訂名稱" }
            return
        }
        let device = context.device
        let payload = UpdateIPCameraCommandPayload(
            ipAddress: device.ipAddress,
            ipcName: device.ipcName.isEmpty ? trimmedCustom : device.ipcName,
            customName: trimmedCustom,
            ipcAccount: input.account.trimmingCharacters(in: .whitespacesAndNewlines),
            // 空字串 = Core 沿用既有密碼，避免 RTSP 串流斷線
            ipcPassword: input.password
        )

        await MainActor.run { isSubmittingEdit = true; editFormError = nil }
        do {
            let command = try await APIClient.shared.sendEdgeCommand(edgeId: edge.edgeId, code: "114", payload: payload)
            let result: EdgeCommandResultDTO<AddedIPCameraDTO> = try await APIClient.shared.fetchEdgeCommandResult(traceId: command.traceId)
            if result.status.lowercased() == "ok" {
                await MainActor.run {
                    isSubmittingEdit = false
                    editSheet = nil
                    infoAlert = .init(title: "已更新攝影機", message: "攝影機資料已成功更新。")
                }
                await fetchAddedCameras(silent: true)
            } else {
                let message = result.errorMessage ?? "更新失敗，請稍後再試。"
                await MainActor.run {
                    isSubmittingEdit = false
                    editFormError = message
                }
            }
        } catch let error as ApiError where error.isNoValidLicense {
            await MainActor.run {
                isSubmittingEdit = false
                editSheet = nil
                showNoLicenseAlert = true
            }
        } catch {
            await MainActor.run {
                isSubmittingEdit = false
                editFormError = error.localizedDescription
            }
        }
    }

    private func removeCamera(_ device: AddedIPCameraDTO) async {
        let normalized = normalizeIPAddress(device.ipAddress)
        await MainActor.run {
            deletingIP = normalized
            addedError = nil
            pendingRemove = nil
        }

        let payload = RemoveIPCameraCommandPayload(ipAddress: device.ipAddress)
        do {
            let command = try await APIClient.shared.sendEdgeCommand(edgeId: edge.edgeId, code: "105", payload: payload)
            let result: EdgeCommandResultDTO<AddIPCameraResultDTO> = try await APIClient.shared.fetchEdgeCommandResult(traceId: command.traceId)

            if result.status.lowercased() == "ok" {
                await MainActor.run {
                    deletingIP = nil
                    if let index = addedDevices.firstIndex(where: { normalizeIPAddress($0.ipAddress) == normalized }) {
                        addedDevices.remove(at: index)
                    }
                    infoAlert = .init(title: "已解除綁定", message: "關聯的偵測策略也已一併移除。")
                }
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await fetchAddedCameras(silent: true)
                }
            } else {
                await MainActor.run {
                    deletingIP = nil
                    addedError = result.errorMessage ?? "解除失敗，請稍後再試。"
                }
            }
        } catch let error as ApiError where error.isNoValidLicense {
            await MainActor.run {
                deletingIP = nil
                showNoLicenseAlert = true
            }
        } catch {
            await MainActor.run {
                deletingIP = nil
                addedError = error.localizedDescription
            }
        }
    }

    private func macForContext(_ context: AddSheetContext) -> String? {
        switch context {
        case .manual: return nil
        case .scan(let device): return device.mac.isEmpty ? nil : device.mac
        }
    }

    private func ipcNameForContext(_ context: AddSheetContext, fallback: String) -> String {
        switch context {
        case .manual: return fallback
        case .scan(let device): return device.name.isEmpty ? fallback : device.name
        }
    }

    private func isAlreadyBoundError(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("already") || lowered.contains("已被綁定") || lowered.contains("已綁定") || lowered.contains("duplicate")
    }
}

// MARK: - Sub views

private struct BoundDeviceRow: View {
    let displayName: String
    let subtitle: String?
    let ipAddress: String
    let macAddress: String
    let isDeleting: Bool
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        GlassContainer(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "video.fill")
                        .font(.title3)
                        .foregroundColor(.successGreen)
                        .padding(8)
                        .background(Color.successGreen.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.bodyMedium.weight(.semibold))
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.captionText.monospaced())
                                .foregroundColor(.textTertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Circle()
                        .fill(Color.successGreen)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.successGreen.opacity(0.25), lineWidth: 4))
                }

                HStack(spacing: 16) {
                    metaItem(label: "IP", value: ipAddress.isEmpty ? "—" : ipAddress)
                    metaItem(label: "MAC", value: macAddress.isEmpty ? "—" : macAddress)
                }

                HStack(spacing: 8) {
                    Spacer()
                    Button(action: onEdit) {
                        Label("編輯", systemImage: "pencil")
                            .font(.captionText.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.primaryBrand.opacity(0.1))
                            .foregroundColor(.primaryBrand)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: onRemove) {
                        if isDeleting {
                            ProgressView().scaleEffect(0.7)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        } else {
                            Label("解除綁定", systemImage: "trash")
                                .font(.captionText.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.errorRed.opacity(0.1))
                                .foregroundColor(.errorRed)
                                .clipShape(Capsule())
                        }
                    }
                    .disabled(isDeleting)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func metaItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.captionText.monospaced())
                .foregroundColor(.textTertiary)
            Text(value)
                .font(.captionText.monospaced())
                .foregroundColor(.textSecondary)
        }
    }
}

private struct ScannedDeviceRow: View {
    let device: IPCameraDeviceDTO
    let displayName: String
    let isAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        GlassContainer(padding: 16) {
            HStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.title3)
                    .foregroundColor(.primaryBrand)
                    .padding(8)
                    .background(Color.primaryBrand.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.bodyMedium.weight(.semibold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    Text(device.ip)
                        .font(.captionText.monospaced())
                        .foregroundColor(.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                if isAdded {
                    Text("已綁定")
                        .font(.captionText.weight(.semibold))
                        .foregroundColor(.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.surface))
                } else {
                    Button(action: onAdd) {
                        Label("綁定", systemImage: "link")
                            .font(.captionText.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.primaryBrand))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Sheets

private struct AddCameraInput {
    var ipAddress: String
    var customName: String
    var account: String
    var password: String
}

private struct EditCameraInput {
    var customName: String
    var account: String
    var password: String
}

private enum AddSheetContext: Identifiable {
    case manual
    case scan(device: IPCameraDeviceDTO)

    var id: String {
        switch self {
        case .manual: return "manual"
        case .scan(let device): return "scan-\(device.id)"
        }
    }

    var titleText: String {
        switch self {
        case .manual: return "手動新增攝影機"
        case .scan: return "綁定攝影機"
        }
    }
}

private struct EditSheetContext: Identifiable {
    let device: AddedIPCameraDTO
    var id: String { device.id }
}

private struct InfoAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct AddCameraSheet: View {
    @Environment(\.dismiss) private var dismiss
    let context: AddSheetContext
    @Binding var error: String?
    let isSubmitting: Bool
    let onSubmit: (AddCameraInput) -> Void

    @State private var ipAddress: String = ""
    @State private var customName: String = ""
    @State private var account: String = ""
    @State private var password: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.titleText)
                            .font(.displaySmall)
                            .foregroundColor(.textPrimary)
                        Text(headerHint)
                            .font(.captionText)
                            .foregroundColor(.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 14) {
                        if case .manual = context {
                            AppTextField(title: "IP 位址", text: $ipAddress)
                        } else if case .scan(let device) = context {
                            AppTextField(title: "IP 位址", text: .constant(device.ip))
                                .disabled(true)
                                .opacity(0.7)
                        }
                        AppTextField(title: "自訂名稱（選填）", text: $customName)
                        AppTextField(title: "帳號（選填）", text: $account)
                        AppTextField(title: "密碼（選填）", text: $password, isSecure: true)
                    }

                    if let error {
                        Text(error)
                            .font(.captionText)
                            .foregroundColor(.errorRed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    PrimaryButton("確認綁定", isLoading: isSubmitting, isDisabled: false) {
                        let resolvedIP: String
                        switch context {
                        case .manual: resolvedIP = ipAddress
                        case .scan(let device): resolvedIP = device.ip
                        }
                        onSubmit(AddCameraInput(
                            ipAddress: resolvedIP,
                            customName: customName,
                            account: account,
                            password: password
                        ))
                    }

                    Spacer(minLength: 24)
                }
                .padding(24)
            }
            .background(Color.secondaryBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private var headerHint: String {
        switch context {
        case .manual:
            return "輸入 IP 與選填的帳密；若攝影機不需驗證可留空。"
        case .scan(let device):
            return "綁定 \(device.name)；若攝影機不需驗證帳密可留空。"
        }
    }
}

private struct EditCameraSheet: View {
    @Environment(\.dismiss) private var dismiss
    let context: EditSheetContext
    @Binding var error: String?
    let isSubmitting: Bool
    let onSubmit: (EditCameraInput) -> Void

    @State private var customName: String = ""
    @State private var account: String = ""
    @State private var password: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("編輯攝影機")
                            .font(.displaySmall)
                            .foregroundColor(.textPrimary)
                        Text("自訂名稱必填；密碼留空 = 沿用現有密碼。")
                            .font(.captionText)
                            .foregroundColor(.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 14) {
                        AppTextField(title: "IP 位址", text: .constant(context.device.ipAddress))
                            .disabled(true)
                            .opacity(0.7)
                        AppTextField(title: "自訂名稱", text: $customName)
                        AppTextField(title: "帳號（選填）", text: $account)
                        AppTextField(title: "新密碼（留空 = 沿用既有）", text: $password, isSecure: true)
                    }

                    if let error {
                        Text(error)
                            .font(.captionText)
                            .foregroundColor(.errorRed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    PrimaryButton("儲存變更", isLoading: isSubmitting, isDisabled: false) {
                        onSubmit(EditCameraInput(
                            customName: customName,
                            account: account,
                            password: password
                        ))
                    }

                    Spacer(minLength: 24)
                }
                .padding(24)
            }
            .background(Color.secondaryBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                customName = context.device.customName
                account = context.device.ipcAccount ?? ""
                password = ""
            }
        }
    }
}
