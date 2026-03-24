import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

// MARK: - 帳號分頁

enum ProfileSheet: Identifiable {
    case displayName
    case password
    case otp

    var id: String {
        switch self {
        case .displayName: return "display-name"
        case .password: return "password"
        case .otp: return "otp"
        }
    }
}

/// AccountView 管理使用者帳號資訊與裝置註冊。
struct AccountView: View {
    @ObservedObject var auth: AuthManager
    @ObservedObject var profileVM: ProfileViewModel
    @Binding var profileSheet: ProfileSheet?
    @AppStorage("appAppearance") private var appearanceSelection = AppearanceMode.system.rawValue

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        header
                        infoCard
                        licenseCard
                        signOutButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 48)
                }
            }
            .sheet(item: $profileSheet) { sheet in
                switch sheet {
                case .displayName:
                    UpdateNameSheet(initialName: auth.userName ?? "") { newName, completion in
                        Task { @MainActor in
                            do {
                                _ = try await auth.updateUserName(to: newName)
                                profileVM.presentMessage("顯示名稱已更新")
                                completion(true)
                                profileSheet = nil
                            } catch {
                                profileVM.presentMessage(error.localizedDescription)
                                completion(false)
                            }
                        }
                    }
                    .presentationDetents([.height(280)])
                case .password:
                    UpdatePasswordSheet { current, newPassword, completion in
                        Task { @MainActor in
                            let success = await profileVM.updatePassword(currentPassword: current, newPassword: newPassword)
                            if success { profileSheet = nil }
                            completion(success)
                        }
                    }
                    .presentationDetents([.medium])
                case .otp:
                    OTPSetupIntroSheet(
                        viewModel: profileVM,
                        enabledInitial: auth.profile?.otpEnabled == true,
                        accountEmail: auth.profile?.email
                    )
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await auth.refreshProfileFromRemote()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("帳號與安全")
                .font(.displaySmall)
                .foregroundStyle(Color.textPrimary)
            Text("管理個人資料與通知設定")
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var infoCard: some View {
        GlassContainer(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Profile Header
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.primaryBrand.opacity(0.1))
                            .frame(width: 60, height: 60)
                        Text(initials(from: auth.profile?.displayName ?? auth.profile?.email ?? "R"))
                            .font(.title2.weight(.bold))
                            .foregroundColor(.primaryBrand)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(auth.profile?.displayName ?? "尚未設定名稱")
                            .font(.bodyLarge.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text(auth.profile?.email ?? "")
                            .font(.captionText)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                }
                .padding(20)

                Divider().background(Color.border)

                // Settings List
                VStack(spacing: 0) {
                    ButtonRow(icon: "pencil", title: "變更使用者名稱") {
                        profileSheet = .displayName
                    }
                    Divider().padding(.leading, 56).background(Color.border)

                    ButtonRow(icon: "lock.rotation", title: "變更使用者密碼") {
                        profileSheet = .password
                    }
                    Divider().padding(.leading, 56).background(Color.border)

                    otpStatusRow
                    Divider().padding(.leading, 56).background(Color.border)

                    appearanceRow
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var licenseCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("授權管理")
                .font(.bodyLarge.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 4)

            GlassContainer(padding: 0) {
                VStack(spacing: 0) {
                    NavigationLink {
                        MyLicensesView()
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "key.horizontal")
                                .foregroundColor(.textSecondary)
                                .frame(width: 24)
                            Text("我的授權")
                                .font(.bodyMedium)
                                .foregroundColor(.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.textTertiary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 56).background(Color.border)

                    NavigationLink {
                        LicensePurchaseView()
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "cart")
                                .foregroundColor(.textSecondary)
                                .frame(width: 24)
                            Text("購買授權")
                                .font(.bodyMedium)
                                .foregroundColor(.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.textTertiary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 56).background(Color.border)

                    Button {
                        if let url = URL(string: "https://introducing.redsafe-tw.com/pricing") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "safari")
                                .foregroundColor(.textSecondary)
                                .frame(width: 24)
                            Text("前往官方網站")
                                .font(.bodyMedium)
                                .foregroundColor(.textPrimary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundColor(.textTertiary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var currentAppearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceSelection) ?? .system
    }

    private var otpStatusRow: some View {
        let enabled = auth.profile?.otpEnabled == true
        return Button {
            profileSheet = .otp
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "key.fill")
                    .foregroundColor(.textSecondary)
                    .frame(width: 24)
                Text("二階段驗證 (OTP)")
                    .font(.bodyMedium)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(enabled ? "已啟用" : "未啟用")
                    .font(.captionText.weight(.medium))
                    .foregroundColor(enabled ? .successGreen : .textTertiary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.textTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var appearanceRow: some View {
        let current = currentAppearance

        return Menu {
            ForEach(AppearanceMode.allCases) { mode in
                Button {
                    appearanceSelection = mode.rawValue
                } label: {
                    if mode == current {
                        Label(mode.displayName, systemImage: "checkmark")
                    } else {
                        Text(mode.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "circle.lefthalf.filled")
                    .foregroundColor(.textSecondary)
                    .frame(width: 24)
                Text("介面模式")
                    .font(.bodyMedium)
                    .foregroundColor(.textPrimary)
                Spacer()
                HStack(spacing: 6) {
                    Text(current.displayName)
                        .font(.captionText.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
    }

    private var signOutButton: some View {
        Button(role: .destructive) {
            auth.signOut()
        } label: {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("登出")
            }
            .font(.bodyLarge.weight(.medium))
            .foregroundColor(.errorRed)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.errorRed.opacity(0.1))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }

    private func initials(from text: String) -> String {
        let components = text.split(separator: " ")
        if let first = components.first, let char = first.first {
            return String(char).uppercased()
        }
        if let first = text.first {
            return String(first).uppercased()
        }
        return "R"
    }
}

// MARK: - Components

private struct ButtonRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .foregroundColor(.textSecondary)
                    .frame(width: 24)
                Text(title)
                    .font(.bodyMedium)
                    .foregroundColor(.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.textTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sheets

private struct UpdateNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    let initialName: String
    let onSubmit: (String, @escaping (Bool) -> Void) -> Void

    init(initialName: String, onSubmit: @escaping (String, @escaping (Bool) -> Void) -> Void) {
        self.initialName = initialName
        self.onSubmit = onSubmit
        _name = State(initialValue: initialName)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                AppTextField(title: "顯示名稱", text: $name)
                PrimaryButton("儲存", isDisabled: name.isEmpty) {
                    onSubmit(name.trimmingCharacters(in: .whitespacesAndNewlines)) { success in
                        if success { dismiss() }
                    }
                }
                Spacer()
            }
            .padding(24)
            .background(Color.secondaryBackground)
            .navigationTitle("變更顯示名稱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                 ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }
}

private struct UpdatePasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSubmitting = false

    let onSubmit: (String, String, @escaping (Bool) -> Void) -> Void

    private var isValid: Bool {
        !currentPassword.isEmpty && !newPassword.isEmpty && newPassword == confirmPassword
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                AppTextField(title: "目前密碼", text: $currentPassword, isSecure: true)
                AppTextField(title: "新密碼", text: $newPassword, isSecure: true)
                AppTextField(title: "確認新密碼", text: $confirmPassword, isSecure: true)
                
                PrimaryButton("更新", isLoading: isSubmitting, isDisabled: !isValid) {
                    isSubmitting = true
                    onSubmit(currentPassword, newPassword) { success in
                        isSubmitting = false
                        if success { dismiss() }
                    }
                }
                Spacer()
            }
            .padding(24)
            .background(Color.secondaryBackground)
            .navigationTitle("變更登入密碼")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                 ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }
}

private struct OTPSetupIntroSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ProfileViewModel
    let enabledInitial: Bool
    let accountEmail: String?

    @State private var showDisableConfirm = false
    @State private var isDisabling = false
    @State private var disableError: String?
    @State private var enabled: Bool = false
    @State private var isEnabling = false
    @State private var enableError: String?
    @State private var otpKey: String?
    @State private var backupCodes: [String] = []
    @State private var showQR: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Status Header
                    HStack {
                         VStack(alignment: .leading, spacing: 4) {
                             Text(enabled ? "已啟用" : "未啟用")
                                 .font(.title2.weight(.bold))
                                 .foregroundColor(enabled ? .successGreen : .textSecondary)
                             Text(enabled ? "您的帳號受到二階段驗證保護" : "啟用以提升帳號安全性")
                                 .font(.captionText)
                                 .foregroundColor(.textSecondary)
                         }
                         Spacer()
                         Image(systemName: enabled ? "shield.check.fill" : "shield.slash.fill")
                             .font(.largeTitle)
                             .foregroundColor(enabled ? .successGreen : .textTertiary)
                    }
                    .padding()
                    .background(Color.surface)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.border))

                    // Action
                    Button {
                        if enabled {
                            showDisableConfirm = true
                        } else {
                            Task {
                                isEnabling = true
                                enableError = nil
                                let result = await viewModel.enableOTP()
                                isEnabling = false
                                if let result {
                                    enabled = true
                                    otpKey = result.otpKey
                                    backupCodes = result.backupCodes
                                    enableError = nil
                                } else {
                                    enableError = viewModel.message
                                }
                            }
                        }
                    } label: {
                        Text(enabled ? "停用二階段驗證" : "立即啟用")
                            .font(.bodyMedium.weight(.semibold))
                            .foregroundColor(enabled ? .errorRed : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                enabled ? Color.errorRed.opacity(0.1) : Color.primaryBrand
                            )
                            .cornerRadius(12)
                    }
                    .disabled(isEnabling || isDisabling)
                    
                    if isEnabling { ProgressView().frame(maxWidth: .infinity) }
                    
                    if let otpKey {
                        Divider()
                        Text("設定資訊")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        
                        // Key Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("密鑰 (Secret Key)")
                                .font(.captionText)
                                .foregroundColor(.textSecondary)
                            HStack {
                                Text(otpKey)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.textPrimary)
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = otpKey
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .foregroundColor(.primaryBrand)
                                }
                            }
                            .padding()
                            .background(Color.surface)
                            .cornerRadius(12)
                        }
                        
                        // QR Section
                        if !showQR {
                            Button("顯示 QR Code") { showQR = true }
                                .font(.bodyMedium)
                                .foregroundColor(.primaryBrand)
                        } else if let qr = qrImage(for: otpKey) {
                            Image(uiImage: qr)
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .frame(width: 200, height: 200)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white)
                                .cornerRadius(12)
                        }
                    }
                    
                    if !backupCodes.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                             Text("備援碼 (Backup Codes)")
                                 .font(.headline)
                                 .foregroundColor(.textPrimary)
                             Text("請務必保存這些代碼，每組僅能使用一次。")
                                 .font(.captionText)
                                 .foregroundColor(.textSecondary)
                             
                             ForEach(backupCodes, id: \.self) { code in
                                 HStack {
                                     Text(code)
                                         .font(.system(.body, design: .monospaced))
                                         .foregroundColor(.textPrimary)
                                     Spacer()
                                     Button {
                                         UIPasteboard.general.string = code
                                     } label: {
                                         Image(systemName: "doc.on.doc")
                                             .foregroundColor(.textTertiary)
                                     }
                                 }
                                 .padding(.vertical, 8)
                                 .padding(.horizontal, 12)
                                 .background(Color.surface)
                                 .cornerRadius(8)
                             }
                        }
                    }
                    
                    Spacer()
                }
                .padding(24)
            }
            .background(Color.secondaryBackground)
            .navigationTitle("二階段驗證")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                 ToolbarItem(placement: .cancellationAction) { Button("關閉") { dismiss() } }
            }
            .task { enabled = enabledInitial }
            .alert("停用二階段驗證？", isPresented: $showDisableConfirm) {
                 Button("停用", role: .destructive) {
                     Task {
                         isDisabling = true
                         let success = await viewModel.disableOTP()
                         isDisabling = false
                         if success {
                             enabled = false
                             otpKey = nil
                             backupCodes = []
                             dismiss()
                         }
                     }
                 }
                 Button("取消", role: .cancel) { }
            }
        }
    }
    
    // Simple QR Gen Logic
    private func qrImage(for secret: String) -> UIImage? {
        let issuer = "RED Safe"
        let account = accountEmail ?? "user"
        let str = "otpauth://totp/\(issuer):\(account)?secret=\(secret)&issuer=\(issuer)&algorithm=SHA1&digits=6&period=30"
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(str.utf8)
        if let output = filter.outputImage {
            if let cg = context.createCGImage(output, from: output.extent) {
                return UIImage(cgImage: cg)
            }
        }
        return nil
    }
}
