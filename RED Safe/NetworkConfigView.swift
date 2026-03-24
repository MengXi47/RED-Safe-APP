import SwiftUI

struct NetworkConfigView: View {
    let edge: EdgeSummary

    @State private var config: EdgeNetworkConfigDTO?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showNoLicenseAlert = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Header / Action
                // Action Card: Network Scanner Header
                GlassContainer(padding: 0) {
                    HStack(spacing: 16) {
                        // Icon / Visual
                        ZStack {
                            Circle()
                                .fill(Color.primaryBrand.opacity(0.1))
                                .frame(width: 56, height: 56)
                            
                            Image(systemName: "network")
                                .font(.title2)
                                .foregroundColor(.primaryBrand)
                                .symbolEffect(.bounce, value: isLoading)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("網路介面配置")
                                .font(.bodyLarge.weight(.semibold))
                                .foregroundColor(.textPrimary)
                            Text(isLoading ? "正在讀取配置..." : "查詢 Edge 的 IP 與網路設定")
                                .font(.captionText)
                                .foregroundColor(.textSecondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            Task { await fetchNetworkConfig() }
                        } label: {
                            Text(isLoading ? "讀取中" : "重新整理")
                                .font(.bodyMedium.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(isLoading ? Color.textTertiary : Color.primaryBrand)
                                        .shadow(color: .shadowSubtle, radius: 4, x: 0, y: 2)
                                )
                        }
                        .disabled(isLoading)
                        .buttonStyle(.plain)
                    }
                    .padding(20)
                }

                if let message = errorMessage {
                    GlassContainer(padding: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.warningOrange)
                            Text(message)
                                .font(.bodyMedium)
                                .foregroundColor(.textPrimary)
                        }
                    }
                }

                // Info Section
                GlassContainer(padding: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("網路資訊")
                            .font(.bodyLarge.weight(.semibold))
                            .foregroundColor(.textPrimary)
                        
                        Divider().background(Color.border)
                        
                        if let config {
                            let dhcpDisplay = config.isDhcpEnabled ? "啟用" : "停用"
                            InfoRow(title: "IP Address", value: config.ipAddress)
                            InfoRow(title: "Gateway", value: config.gateway)
                            InfoRow(title: "Subnet Mask", value: config.subnetMask)
                            InfoRow(title: "DHCP", value: dhcpDisplay)
                        } else {
                            Text(isLoading ? "正在取得資料…" : "尚未取得資料")
                                .font(.bodyMedium)
                                .foregroundColor(.textTertiary)
                                .padding(.vertical, 8)
                        }
                    }
                }
                
                if let dns = config?.dns, !dns.isEmpty {
                    GlassContainer(padding: 24) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("DNS")
                                .font(.bodyLarge.weight(.semibold))
                                .foregroundColor(.textPrimary)
                            Divider().background(Color.border)
                            Text(dns)
                                .font(.bodyMedium.monospaced())
                                .foregroundColor(.textPrimary)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color.appBackground)
        .navigationTitle("網路配置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .offlineOverlay(isOnline: edge.isOnline)
        .task {
            await fetchNetworkConfig()
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

    private func fetchNetworkConfig() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        do {
            let command = try await APIClient.shared.sendEdgeCommand(edgeId: edge.edgeId, code: "102")
            let result: EdgeCommandResultDTO<EdgeNetworkConfigDTO> = try await APIClient.shared.fetchEdgeCommandResult(traceId: command.traceId)
            await MainActor.run {
                self.config = result.result
                self.isLoading = false
                self.errorMessage = nil
            }
        } catch let error as ApiError where error.isNoValidLicense {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = "此裝置尚無有效授權"
                self.showNoLicenseAlert = true
            }
        } catch {
            await MainActor.run {
                self.config = nil
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }
}

private struct InfoRow: View {
    let title: String
    let value: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.bodyMedium.weight(.medium))
                .foregroundColor(.textSecondary)
                .frame(width: 120, alignment: .leading)
            Text(value?.isEmpty == false ? value! : "—")
                .font(.bodyMedium.monospaced())
                .foregroundColor(.textPrimary)
        }
    }
}
