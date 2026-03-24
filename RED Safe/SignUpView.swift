import SwiftUI
import UIKit

struct SignUpView: View {
    @StateObject private var viewModel = SignUpViewModel()
    @FocusState private var focusedField: SignUpViewModel.Field?
    @Environment(\.dismiss) private var dismiss
    
    // Animation states
    @State private var appear = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 32) {
                        Spacer().frame(height: 20)
                        
                        // MARK: - Header
                        VStack(spacing: 8) {
                            Text("Create Account")
                                .font(.displayLarge)
                                .foregroundColor(.textPrimary)
                            Text("註冊以開始保護您的家庭")
                                .font(.bodyMedium)
                                .foregroundColor(.textSecondary)
                        }
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 20)
                        .animation(.easeOut(duration: 0.6), value: appear)
                        
                        // MARK: - Form
                        GlassContainer(padding: 24) {
                            VStack(spacing: 24) {
                                VStack(spacing: 16) {
                                    AppTextField(
                                        title: "顯示名稱",
                                        text: $viewModel.displayName,
                                        icon: "person",
                                        errorMessage: viewModel.displayNameErrorMessage
                                    )
                                    .focused($focusedField, equals: .displayName)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .email }
                                    
                                    AppTextField(
                                        title: "電子郵件",
                                        text: $viewModel.email,
                                        icon: "envelope",
                                        keyboardType: .emailAddress,
                                        errorMessage: viewModel.emailErrorMessage
                                    )
                                    .focused($focusedField, equals: .email)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .password }
                                    
                                    AppTextField(
                                        title: "設定密碼",
                                        text: $viewModel.password,
                                        icon: "lock",
                                        isSecure: true,
                                        errorMessage: viewModel.passwordErrorMessage
                                    )
                                    .focused($focusedField, equals: .password)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .confirmPassword }
                                    
                                    AppTextField(
                                        title: "確認密碼",
                                        text: $viewModel.confirmPassword,
                                        icon: "lock.shield",
                                        isSecure: true,
                                        errorMessage: viewModel.confirmPasswordErrorMessage
                                    )
                                    .focused($focusedField, equals: .confirmPassword)
                                    .submitLabel(.done)
                                    .onSubmit { Task { await viewModel.submit() } }
                                }
                                
                                // Password Hints
                                if !viewModel.password.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("密碼強度要求：")
                                            .font(.captionText)
                                            .foregroundColor(.textSecondary)
                                        HStack(spacing: 12) {
                                            PasswordRequirementView(isValid: viewModel.password.count >= 8, text: "8+ 字元")
                                            PasswordRequirementView(isValid: viewModel.password.range(of: "[0-9]", options: .regularExpression) != nil, text: "數字")
                                            PasswordRequirementView(isValid: viewModel.password.range(of: "[A-Z]", options: .regularExpression) != nil, text: "大寫字母")
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.bottom, 8)
                                    .transition(.opacity)
                                }
                                
                                PrimaryButton(
                                    "註冊",
                                    isLoading: viewModel.isSubmitting,
                                    isDisabled: !viewModel.canSubmit
                                ) {
                                    Task { await viewModel.submit() }
                                }
                                
                                Button {
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text("已有帳號？")
                                            .foregroundColor(.textSecondary)
                                        Text("直接登入")
                                            .foregroundColor(.primaryBrand)
                                            .fontWeight(.semibold)
                                    }
                                    .font(.bodyMedium)
                                }
                            }
                        }
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 40)
                        .animation(.easeOut(duration: 0.6).delay(0.2), value: appear)
                        
                        // Tips
                        VStack(spacing: 16) {
                            Text("為什麼要註冊？")
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                            
                            VStack(spacing: 12) {
                                TipRow(icon: "shield.check.fill", title: "最高安全標準", subtitle: "所有資料皆經過加密處理，確保您的隱私無虞")
                                TipRow(icon: "icloud.and.arrow.down.fill", title: "雲端同步", subtitle: "在您的所有裝置上即時存取 Edge 狀態")
                            }
                        }
                        .padding(.horizontal, 24)
                        .opacity(appear ? 1 : 0)
                        .animation(.easeOut(duration: 0.6).delay(0.4), value: appear)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .onAppear {
                appear = true
            }
            .onTapGesture {
                focusedField = nil
            }
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                    }
                }
            }
            // Global Banner Overlay
            .overlay(alignment: .top) {
                if let banner = viewModel.banner {
                    BannerView(banner: banner)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(), value: viewModel.banner)
            // Sheet for Email Verification
            .sheet(item: $viewModel.pendingEmailVerification) { pending in
                EmailVerificationSheet(viewModel: viewModel, pending: pending)
            }
        }
    }
}

// MARK: - Components

private struct PasswordRequirementView: View {
    let isValid: Bool
    let text: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isValid ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isValid ? .successGreen : .textTertiary)
                .font(.caption)
            Text(text)
                .font(.captionText)
                .foregroundColor(isValid ? .successGreen : .textTertiary)
        }
    }
}

private struct TipRow: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.primaryBrand.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .foregroundColor(.primaryBrand)
                    .font(.bodyMedium)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.bodyMedium.weight(.semibold))
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .font(.captionText)
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.surface)
                .shadow(color: .shadowSubtle, radius: 12, x: 0, y: 4)
        )
    }
}

private struct BannerView: View {
    let banner: SignUpViewModel.Banner
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: banner.kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(banner.kind == .success ? .successGreen : .errorRed)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title)
                    .font(.bodyMedium.weight(.semibold))
                    .foregroundColor(.textPrimary)
                Text(banner.message)
                    .font(.captionText)
                    .foregroundColor(.textSecondary)
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(16)
        .shadow(color: .shadowStrong, radius: 16, x: 0, y: 8)
        .padding(.horizontal, 20)
    }
}

private struct EmailVerificationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SignUpViewModel
    let pending: SignUpViewModel.PendingEmailVerification
    
    @State private var code: String = ""
    @FocusState private var focusedField: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.secondaryBackground.ignoresSafeArea()
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("信箱驗證")
                            .font(.displaySmall)
                            .foregroundColor(.textPrimary)
                        Text("我們已將驗證碼發送至 \(pending.displayEmail)")
                            .font(.bodyMedium)
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 32)
                    
                    AppTextField(title: "6 碼驗證碼", text: $code, icon: "envelope.badge", keyboardType: .numberPad)
                        .focused($focusedField)
                    
                    PrimaryButton("驗證", isLoading: viewModel.isVerifyingEmail, isDisabled: code.count < 6) {
                        Task {
                            let result = await viewModel.completeEmailVerification(code: code)
                            if case .success = result { dismiss() }
                        }
                    }
                    
                    Button("重新發送") {
                        Task { await viewModel.resendVerificationEmail() }
                    }
                    .font(.bodyMedium)
                    .foregroundColor(viewModel.isResendingEmailCode ? .textTertiary : .primaryBrand)
                    .disabled(viewModel.isResendingEmailCode)
                    
                    Spacer()
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

// MARK: - View Model

@MainActor
final class SignUpViewModel: ObservableObject {
    enum Field: Hashable {
        case displayName, email, password, confirmPassword
    }

    struct Banner: Identifiable, Equatable {
        enum Kind { case success, error }
        let id = UUID()
        let title: String
        let message: String
        let kind: Kind
    }

    struct PendingEmailVerification: Identifiable, Equatable {
        let id = UUID()
        let context: AuthManager.EmailVerificationContext
        let displayEmail: String
    }

    @Published var displayName = ""
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    
    @Published var isSubmitting = false
    @Published var banner: Banner?
    @Published var pendingEmailVerification: PendingEmailVerification?
    @Published var isVerifyingEmail = false
    @Published var isResendingEmailCode = false
    
    // Validation flags
    @Published var displayNameValidated = false
    @Published var emailValidated = false
    @Published var passwordValidated = false
    @Published var confirmPasswordValidated = false

    private var bannerDismissTask: Task<Void, Never>?
    
    // Computed Properties
    var trimmedDisplayName: String { displayName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    
    var isDisplayNameValid: Bool { !trimmedDisplayName.isEmpty }
    var isEmailValid: Bool {
        let regex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: trimmedEmail)
    }
    var isPasswordValid: Bool { password.count >= 6 } // Basic check, detailed check in UI
    var isConfirmPasswordValid: Bool { confirmPassword == password }
    
    var canSubmit: Bool {
        isDisplayNameValid && isEmailValid && isPasswordValid && isConfirmPasswordValid && !isSubmitting
    }
    
    // Error Messages
    var displayNameErrorMessage: String? {
        (displayNameValidated && !isDisplayNameValid) ? "名稱不可為空" : nil
    }
    var emailErrorMessage: String? {
        (emailValidated && !isEmailValid) ? "格式錯誤" : nil
    }
    var passwordErrorMessage: String? {
        (passwordValidated && !isPasswordValid) ? "密碼需至少 6 碼" : nil
    }
    var confirmPasswordErrorMessage: String? {
        (confirmPasswordValidated && !isConfirmPasswordValid) ? "密碼不一致" : nil
    }

    func submit() async {
        // Trigger validation visual
        displayNameValidated = true
        emailValidated = true
        passwordValidated = true
        confirmPasswordValidated = true
        
        guard canSubmit else {
            showBanner(title: "請檢查欄位", message: "部分資料格式有誤", kind: .error)
            return
        }
        
        isSubmitting = true
        defer { isSubmitting = false }
        
        do {
            // 1) 呼叫註冊 API
            let response = try await APIClient.shared.signUp(
                email: trimmedEmail,
                userName: trimmedDisplayName,
                password: password
            )
            
            // 2) 送出驗證信
            _ = try await APIClient.shared.requestEmailVerification(userId: response.userId)
            
            // 3) 建立驗證流程上下文並顯示驗證畫面
            let context = AuthManager.EmailVerificationContext(
                email: trimmedEmail,
                password: password,
                userId: response.userId
            )
            pendingEmailVerification = PendingEmailVerification(context: context, displayEmail: trimmedEmail)
        } catch {
            showBanner(title: "註冊失敗", message: error.localizedDescription, kind: .error)
        }
    }
    
    func completeEmailVerification(code: String) async -> Result<Void, Error> {
        guard let pending = pendingEmailVerification else { return .failure(SignInViewModel.EmailVerificationFlowError.missingContext) }
        
        isVerifyingEmail = true
        defer { isVerifyingEmail = false }
        
        do {
            try await AuthManager.shared.verifyEmail(context: pending.context, code: code)
            pendingEmailVerification = nil
            showBanner(title: "驗證成功", message: "註冊完成！", kind: .success)
            return .success(())
        } catch {
            showBanner(title: "驗證失敗", message: error.localizedDescription, kind: .error)
            return .failure(error)
        }
    }
    
    func resendVerificationEmail() async {
        guard let pending = pendingEmailVerification else { return }
        isResendingEmailCode = true
        defer { isResendingEmailCode = false }
        
        do {
            try await AuthManager.shared.resendEmailVerification(for: pending.context)
            showBanner(title: "已發送", message: "請檢查您的信箱", kind: .success)
        } catch {
            showBanner(title: "發送失敗", message: error.localizedDescription, kind: .error)
        }
    }

    private func showBanner(title: String, message: String, kind: Banner.Kind) {
        bannerDismissTask?.cancel()
        withAnimation {
            banner = Banner(title: title, message: message, kind: kind)
        }
        bannerDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                withAnimation { banner = nil }
            }
        }
    }
}
