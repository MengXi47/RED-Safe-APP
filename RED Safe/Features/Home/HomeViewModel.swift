import Foundation

/// HomeViewModel 專責處理裝置清單與相關操作，維持 UI 與網路層的清楚界線。
@MainActor
final class HomeViewModel: ObservableObject {
    @Published var edges: [EdgeSummary] = []
    @Published var isLoading: Bool = false
    @Published var message: String?
    @Published var showMessage: Bool = false

    @Published var resourceUsage: [String: EdgeResourceUsageDTO] = [:]
    @Published var showNoLicenseAlert: Bool = false
    @Published var noLicenseAlertMessage: String = ""
    private var monitoringTimer: Timer?
    private var connectivityTask: Task<Void, Never>?

    /// 載入使用者綁定的 Edge 清單。
    func loadEdges(showIndicator: Bool = true) {
        Task { @MainActor in
            if showIndicator { isLoading = true }
             defer {
                 if showIndicator { isLoading = false }
             }

             do {
                 let fetched = try await APIClient.shared.fetchEdgeList()
                 self.edges = sortEdges(fetched)
                 if fetched.isEmpty {
                     self.showTempMessage("尚未綁定裝置，請新增裝置。")
                 }
             } catch {
                 self.showTempMessage(error.localizedDescription)
             }
         }
    }
    
    // MARK: - Resource Monitoring

    func startResourceMonitoring() {
        stopResourceMonitoring()

        // 啟動 connectivity 監聽：離線暫停、上線恢復
        connectivityTask = Task { [weak self] in
            for await isConnected in NetworkMonitor.shared.connectivityUpdates {
                guard let self, !Task.isCancelled else { return }
                if isConnected {
                    self.startTimer()
                    self.fetchResources()
                } else {
                    self.stopTimer()
                }
            }
        }

        // 若目前有網路，立即開始
        if NetworkMonitor.shared.isConnected {
            fetchResources()
            startTimer()
        }
    }

    private func startTimer() {
        stopTimer()
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.fetchResources()
        }
    }

    private func stopTimer() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }

    func stopResourceMonitoring() {
        stopTimer()
        connectivityTask?.cancel()
        connectivityTask = nil
    }

    private func fetchResources() {
        guard !edges.isEmpty, NetworkMonitor.shared.isConnected else { return }
        
        // Filter only online edges or try all? Requirement says "Dashboard active". 
        // Assuming we try all or let the user decide. Typically only online edges respond.
        // We will loop through known online edges to reduce noise, or just all.
        // Optimistically trying all bound edges.
        
        Task { @MainActor in
            for edge in edges {
                // Only poll online devices
                guard let isOnline = edge.isOnline, isOnline else { continue }
                
                do {
                    let command = try await APIClient.shared.sendEdgeCommand(edgeId: edge.edgeId, code: "108")
                    let result: EdgeCommandResultDTO<EdgeResourceUsageDTO> = try await APIClient.shared.fetchEdgeCommandResult(traceId: command.traceId)

                    if result.status.lowercased() == "ok", let usage = result.result {
                        self.resourceUsage[edge.edgeId] = usage
                    }
                } catch let error as ApiError where error.isNoValidLicense {
                    // 背景輪詢遇到無授權錯誤時靜默處理，不中斷監控流程
                    _ = error
                } catch {
                     // Silently fail for monitoring to avoid spamming UI
                }
            }
        }
    }

    /// 嘗試綁定新 Edge 裝置。
    func bindEdge(edgeId: String, name: String, password: String) {
        Task { @MainActor in
            isLoading = true
            defer { isLoading = false }

            do {
                _ = try await APIClient.shared.bindEdge(edgeId: edgeId, displayName: name, edgePassword: password)
                showTempMessage("綁定成功")
                loadEdges(showIndicator: false)
            } catch {
                showTempMessage(error.localizedDescription)
            }
        }
    }

    /// 解除指定 Edge 的綁定。
    func unbindEdge(edgeId: String) {
        Task { @MainActor in
            isLoading = true
            defer { isLoading = false }

            do {
                _ = try await APIClient.shared.unbindEdge(edgeId: edgeId)
                showTempMessage("已解除綁定")
                edges.removeAll { $0.edgeId == edgeId }
                resourceUsage.removeValue(forKey: edgeId)
            } catch {
                showTempMessage(error.localizedDescription)
            }
        }
    }

    /// 更新 Edge 顯示名稱。
    func renameEdge(edgeId: String, newName: String) {
        Task { @MainActor in
            isLoading = true
            defer { isLoading = false }

            do {
                _ = try await APIClient.shared.updateEdgeName(edgeId: edgeId, newName: newName)
                if let index = edges.firstIndex(where: { $0.edgeId == edgeId }) {
                    let edge = edges[index]
                    edges[index] = EdgeSummary(edgeId: edge.edgeId, displayName: newName, isOnline: edge.isOnline)
                    edges = sortEdges(edges)
                }
                showTempMessage("名稱已更新")
            } catch {
                showTempMessage(error.localizedDescription)
            }
        }
    }

    /// 更新 Edge 密碼。
    func updateEdgePassword(edgeId: String, currentPassword: String, newPassword: String) {
        Task { @MainActor in
            isLoading = true
            defer { isLoading = false }

            do {
                _ = try await APIClient.shared.updateEdgePassword(edgeId: edgeId, currentPassword: currentPassword, newPassword: newPassword)
                showTempMessage("Edge 密碼已更新")
            } catch {
                showTempMessage(error.localizedDescription)
            }
        }
    }

    // MARK: - License

    /// 啟用授權金鑰並綁定至指定 Edge。
    func activateLicense(licenseKey: String, edgeId: String, edgePassword: String) async -> Bool {
        do {
            let response = try await APIClient.shared.activateLicense(
                licenseKey: licenseKey,
                edgeId: edgeId,
                edgePassword: edgePassword
            )
            if response.errorCode.isSuccess {
                showTempMessage("授權啟用成功")
                return true
            } else {
                showTempMessage(response.errorCode.message)
                return false
            }
        } catch {
            showTempMessage(error.localizedDescription)
            return false
        }
    }

    /// 取得指定 Edge 的授權資訊。
    func fetchLicenseInfo(edgeId: String) async -> LicenseInfoResponse? {
        do {
            return try await APIClient.shared.fetchEdgeLicense(edgeId: edgeId)
        } catch {
            return nil
        }
    }

    /// 顯示無授權提示彈窗。
    func presentNoLicenseAlert(for edgeId: String) {
        noLicenseAlertMessage = "此裝置尚無有效授權，無法執行指令。請至 introducing.redsafe-tw.com 購買授權。"
        showNoLicenseAlert = true
    }

    /// 顯示短暫提示訊息。
    private func showTempMessage(_ text: String) {
        message = text
        showMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.showMessage = false
        }
    }

    private func normalizedName(for edge: EdgeSummary) -> String {
        let trimmed = (edge.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? edge.edgeId : trimmed
    }

    private func sortEdges(_ list: [EdgeSummary]) -> [EdgeSummary] {
        list.sorted { lhs, rhs in
            let leftName = normalizedName(for: lhs)
            let rightName = normalizedName(for: rhs)

            let comparison = leftName.localizedCaseInsensitiveCompare(rightName)
            if comparison == .orderedSame {
                return lhs.edgeId.localizedCaseInsensitiveCompare(rhs.edgeId) == .orderedAscending
            }
            return comparison == .orderedAscending
        }
    }
}
