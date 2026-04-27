import SwiftUI

struct IPCameraConfigView: View {
    let edge: EdgeSummary

    @State private var devices: [IPCameraDeviceDTO] = []
    @State private var addedDevices: [AddedIPCameraDTO] = []
    @State private var isLoading = false
    @State private var isFetchingAdded = false
    @State private var errorMessage: String?
    @State private var addedErrorMessage: String?
    @State private var lastTraceId: String?
    @State private var selectedDeviceForAdd: IPCameraDeviceDTO?
    @State private var addCustomName: String = ""
    @State private var addAccount: String = ""
    @State private var addPassword: String = ""
    @State private var addFormError: String?
    @State private var isSubmittingAdd = false
    @State private var addAlert: AddCameraAlert?
    @State private var deletingIP: String?
    @State private var showNoLicenseAlert = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Action Card
                // Action Card: Scanner Header
                GlassContainer(padding: 0) {
                    HStack(spacing: 16) {
                        // Icon / Visual
                        ZStack {
                            Circle()
                                .fill(Color.primaryBrand.opacity(0.1))
                                .frame(width: 56, height: 56)
                            
                            Image(systemName: isLoading ? "rays" : "dot.radiowaves.left.and.right")
                                .font(.title2)
                                .foregroundColor(.primaryBrand)
                                .symbolEffect(.variableColor.iterative.reversing, isActive: isLoading)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("掃描 IP Camera")
                                .font(.bodyLarge.weight(.semibold))
                                .foregroundColor(.textPrimary)
                            Text(isLoading ? "正在搜尋裝置..." : "偵測區網內的攝影機")
                                .font(.captionText)
                                .foregroundColor(.textSecondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            Task { await triggerScan() }
                        } label: {
                            Text(isLoading ? "掃描中" : "開始")
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

                // Scanned Devices Section
                VStack(alignment: .leading, spacing: 12) {
                     Text("掃描結果")
                         .font(.bodyLarge.weight(.semibold))
                         .foregroundColor(.textSecondary)
                         .padding(.horizontal, 4)
                     
                     if devices.isEmpty {
                         GlassContainer(padding: 24) {
                             Text(isLoading ? "正在取得資料…" : "尚未取得資料")
                                 .font(.bodyMedium)
                                 .foregroundColor(.textTertiary)
                                 .frame(maxWidth: .infinity, alignment: .center)
                         }
                     } else {
                         LazyVStack(spacing: 12) {
                             ForEach(devices) { device in
                                 ScannedDeviceRow(
                                     device: device,
                                     isAdded: isDeviceAlreadyAdded(device),
                                     onAdd: { openAddSheet(for: device) }
                                 )
                             }
                         }
                     }
                }
                
                // Added Devices Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("已新增的攝影機")
                        .font(.bodyLarge.weight(.semibold))
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal, 4)
                    
                    if isFetchingAdded {
                         GlassContainer(padding: 24) {
                             HStack {
                                 ProgressView()
                                 Text("正在載入...")
                                     .font(.bodyMedium)
                                     .foregroundColor(.textSecondary)
                             }
                             .frame(maxWidth: .infinity)
                         }
                    } else if addedDevices.isEmpty {
                        GlassContainer(padding: 24) {
                            Text("目前沒有已新增的攝影機")
                                .font(.bodyMedium)
                                .foregroundColor(.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(addedDevices) { device in
                                AddedDeviceRow(
                                    device: device,
                                    isDeleting: isDeleting(device),
                                    onDelete: { Task { await removeCamera(device) } }
                                )
                            }
                        }
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background(Color.appBackground)
        .navigationTitle("IP Camera 配置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .offlineOverlay(isOnline: edge.isOnline)
        .task(id: edge.edgeId) {
            await fetchAddedCameras()
        }
        .sheet(item: $selectedDeviceForAdd, onDismiss: resetAddForm) { device in
             AddCameraSheet(
                 device: device,
                 customName: $addCustomName,
                 account: $addAccount,
                 password: $addPassword,
                 error: $addFormError,
                 isSubmitting: isSubmittingAdd,
                 onSubmit: { Task { await submitAdd(for: device) } }
             )
        }
        .alert(item: $addAlert) { alert in
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
    }
    
    // Logic Methods (Kept primarily same)
    private func triggerScan() async {
        await MainActor.run { isLoading = true; errorMessage = nil }
        do {
            let command = try await APIClient.shared.sendEdgeCommand(edgeId: edge.edgeId, code: "101")
            let result: EdgeCommandResultDTO<[IPCameraDeviceDTO]> = try await APIClient.shared.fetchEdgeCommandResult(traceId: command.traceId)
            await MainActor.run {
                self.devices = result.result ?? []
                self.isLoading = false
                if result.result == nil, let msg = result.errorMessage {
                    self.errorMessage = msg
                }
            }
        } catch let error as ApiError where error.isNoValidLicense {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = "此裝置尚無有效授權"
                self.showNoLicenseAlert = true
            }
        } catch {
            await MainActor.run {
                self.devices = []
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func fetchAddedCameras() async {
        await MainActor.run { isFetchingAdded = true; addedErrorMessage = nil }
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
                self.addedErrorMessage = "此裝置尚無有效授權"
                self.showNoLicenseAlert = true
            }
        } catch {
            await MainActor.run {
                self.isFetchingAdded = false
                self.addedErrorMessage = error.localizedDescription
            }
        }
    }

    private func openAddSheet(for device: IPCameraDeviceDTO) {
        resetAddForm()
        selectedDeviceForAdd = device
    }

    private func resetAddForm() {
        addCustomName = ""
        addAccount = ""
        addPassword = ""
        addFormError = nil
        isSubmittingAdd = false
    }

    private func submitAdd(for device: IPCameraDeviceDTO) async {
        let trimmedName = addCustomName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? device.name : trimmedName

        let payload = AddIPCameraCommandPayload(
            ip: device.ip,
            mac: device.mac,
            ipcName: device.name,
            customName: finalName,
            ipcAccount: addAccount.trimmingCharacters(in: .whitespacesAndNewlines),
            ipcPassword: addPassword
        )

        await MainActor.run { isSubmittingAdd = true; addFormError = nil }

        do {
            let command = try await APIClient.shared.sendEdgeCommand(edgeId: edge.edgeId, code: "104", payload: payload)
            let result: EdgeCommandResultDTO<AddIPCameraResultDTO> = try await APIClient.shared.fetchEdgeCommandResult(traceId: command.traceId)

            let trimmedError = result.result?.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.status.lowercased() == "ok", (trimmedError?.isEmpty ?? true) {
                await MainActor.run {
                    isSubmittingAdd = false
                    selectedDeviceForAdd = nil
                    addAlert = AddCameraAlert(title: "新增成功", message: "攝影機已成功新增。")
                }
                await fetchAddedCameras()
            } else {
                let message = trimmedError?.isEmpty == false
                    ? trimmedError!
                    : (result.errorMessage ?? "新增失敗，請稍後再試。")
                await MainActor.run {
                    isSubmittingAdd = false
                    addFormError = message
                }
            }
        } catch let error as ApiError where error.isNoValidLicense {
            await MainActor.run {
                isSubmittingAdd = false
                selectedDeviceForAdd = nil
                showNoLicenseAlert = true
            }
        } catch {
            await MainActor.run {
                isSubmittingAdd = false
                addFormError = error.localizedDescription
            }
        }
    }
    
    private func removeCamera(_ device: AddedIPCameraDTO) async {
         let normalized = normalizeIPAddress(device.ipAddress)
         await MainActor.run { deletingIP = normalized; addedErrorMessage = nil }

         let payload = RemoveIPCameraCommandPayload(ip: device.ipAddress)

         do {
             let command = try await APIClient.shared.sendEdgeCommand(edgeId: edge.edgeId, code: "105", payload: payload)
             let result: EdgeCommandResultDTO<AddIPCameraResultDTO> = try await APIClient.shared.fetchEdgeCommandResult(traceId: command.traceId)

             if result.status.lowercased() == "ok" {
                 await MainActor.run {
                     deletingIP = nil
                     // Optimistic update: Remove locally
                     if let index = addedDevices.firstIndex(where: { normalizeIPAddress($0.ipAddress) == normalized }) {
                         addedDevices.remove(at: index)
                     }
                     addAlert = AddCameraAlert(title: "刪除成功", message: "攝影機已成功刪除。")
                 }
                 Task {
                      try? await Task.sleep(nanoseconds: 1 * 1_000_000_000)
                      await fetchAddedCameras()
                 }
             } else {
                  await MainActor.run { deletingIP = nil; addedErrorMessage = result.errorMessage ?? "刪除失敗" }
             }
         } catch let error as ApiError where error.isNoValidLicense {
             await MainActor.run {
                 deletingIP = nil
                 showNoLicenseAlert = true
             }
         } catch {
             await MainActor.run {
                 deletingIP = nil
                 addedErrorMessage = error.localizedDescription
             }
         }
     }
     
     private func isDeviceAlreadyAdded(_ device: IPCameraDeviceDTO) -> Bool {
         let deviceIP = normalizeIPAddress(device.ip)
         guard !deviceIP.isEmpty else { return false }
         return addedDevices.contains { normalizeIPAddress($0.ipAddress) == deviceIP }
     }

     private func isDeleting(_ device: AddedIPCameraDTO) -> Bool {
         guard let deletingIP else { return false }
         return normalizeIPAddress(device.ipAddress) == deletingIP
     }

     private func normalizeIPAddress(_ value: String) -> String {
         value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
     }
}

// MARK: - Subviews

private struct ScannedDeviceRow: View {
    let device: IPCameraDeviceDTO
    let isAdded: Bool
    let onAdd: () -> Void
    
    var body: some View {
        GlassContainer(padding: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "camera.fill")
                            .foregroundColor(.primaryBrand)
                        Text(device.name)
                            .font(.bodyMedium.weight(.semibold))
                            .foregroundColor(.textPrimary)
                    }
                    Text(device.ip)
                        .font(.captionText.monospaced())
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                
                if isAdded {
                    Text("已新增")
                        .font(.captionText.weight(.medium))
                        .foregroundColor(.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.surface)
                        .cornerRadius(8)
                } else {
                    Button(action: onAdd) {
                        Text("新增")
                            .font(.captionText.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.primaryBrand)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct AddedDeviceRow: View {
    let device: AddedIPCameraDTO
    let isDeleting: Bool
    let onDelete: () -> Void
    
    var body: some View {
        GlassContainer(padding: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "video.fill")
                            .foregroundColor(.successGreen)
                        Text(displayName(for: device))
                            .font(.bodyMedium.weight(.semibold))
                            .foregroundColor(.textPrimary)
                    }
                    Text(device.ipAddress.isEmpty ? device.macAddress : device.ipAddress)
                        .font(.captionText.monospaced())
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                
                Button(action: onDelete) {
                    if isDeleting {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "trash")
                            .foregroundColor(.errorRed)
                            .padding(8)
                            .background(Color.errorRed.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
                .disabled(isDeleting)
                .buttonStyle(.plain)
            }
        }
    }
    
    private func displayName(for device: AddedIPCameraDTO) -> String {
         if !device.customName.isEmpty { return device.customName }
         if !device.ipcName.isEmpty { return device.ipcName }
         return device.ipAddress.isEmpty ? device.macAddress : device.ipAddress
     }
}

private struct AddCameraSheet: View {
    @Environment(\.dismiss) private var dismiss
    let device: IPCameraDeviceDTO
    @Binding var customName: String
    @Binding var account: String
    @Binding var password: String
    @Binding var error: String?
    let isSubmitting: Bool
    let onSubmit: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                 VStack(alignment: .leading, spacing: 12) {
                     Text("新增攝影機")
                         .font(.displaySmall)
                         .foregroundColor(.textPrimary)
                     Text("請輸入攝影機的登入資訊（若需要）")
                         .font(.bodyMedium)
                         .foregroundColor(.textSecondary)
                 }
                 .frame(maxWidth: .infinity, alignment: .leading)
                 .padding(.top, 24)
                 
                 VStack(spacing: 16) {
                     AppTextField(title: "自訂名稱 (選填)", text: $customName)
                     AppTextField(title: "帳號", text: $account)
                     AppTextField(title: "密碼", text: $password, isSecure: true)
                 }
                 
                 if let error {
                     Text(error)
                         .font(.captionText)
                         .foregroundColor(.errorRed)
                 }
                 
                 PrimaryButton("確認新增", isLoading: isSubmitting, isDisabled: false, action: onSubmit)
                 Spacer()
            }
            .padding(24)
            .background(Color.secondaryBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }
}

private struct AddCameraAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
