import SwiftUI
import UIKit

/// SignInView 提供使用者登入介面，Refactored for Crystal Clean Design.
struct SignInView: View {
    @StateObject private var viewModel = SignInViewModel()
    @FocusState private var focusedField: SignInViewModel.Field?
    
    // Animation states
    @State private var appear = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 40) {
                        Spacer().frame(height: 40)
                        
                        // MARK: - Hero Section
                        VStack(spacing: 16) {
                            Image("RED_Safe_icon1")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 120, height: 120)
                                .shadow(color: .shadowSubtle, radius: 20, x: 0, y: 10)
                                .scaleEffect(appear ? 1 : 0.8)
                                .opacity(appear ? 1 : 0)
                                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: appear)
                            
                            VStack(spacing: 8) {
                                Text("Welcome Back")
                                    .font(.displayLarge)
                                    .foregroundColor(.textPrimary)
                                Text("登入以管理您的 Edge 裝置")
                                    .font(.bodyMedium)
                                    .foregroundColor(.textSecondary)
                            }
                            .offset(y: appear ? 0 : 20)
                            .opacity(appear ? 1 : 0)
                            .animation(.easeOut(duration: 0.6).delay(0.1), value: appear)
                        }
                        
                        // MARK: - Form Section
                        GlassContainer(padding: 24) {
                            VStack(spacing: 24) {
                                VStack(spacing: 16) {
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
                                        title: "密碼",
                                        text: $viewModel.password,
                                        icon: "lock",
                                        isSecure: true,
                                        errorMessage: viewModel.passwordErrorMessage
                                    )
                                    .focused($focusedField, equals: .password)
                                    .submitLabel(.go)
                                    .onSubmit { Task { await viewModel.submit() } }
                                }
                                
                                PrimaryButton(
                                    "登入",
                                    isLoading: viewModel.isSubmitting,
                                    isDisabled: !viewModel.canSubmit
                                ) {
                                    Task { await viewModel.submit() }
                                }
                                
                                HStack {
                                    Rectangle().fill(Color.border).frame(height: 1)
                                    Text("OR")
                                        .font(.captionText)
                                        .foregroundColor(.textSecondary)
                                    Rectangle().fill(Color.border).frame(height: 1)
                                }
                                
                                NavigationLink(destination: SignUpView()) {
                                    Text("還沒有帳號？立即註冊")
                                        .font(.bodyMedium.weight(.semibold))
                                        .foregroundColor(.primaryBrand)
                                }
                            }
                        }
                        .offset(y: appear ? 0 : 40)
                        .opacity(appear ? 1 : 0)
                        .animation(.easeOut(duration: 0.6).delay(0.2), value: appear)
                        
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
            // Global Banner Overlay
            .overlay(alignment: .top) {
                if let banner = viewModel.banner {
                    BannerView(banner: banner)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(), value: viewModel.banner)
            
            // Sheets
            .sheet(item: $viewModel.pendingOTP) { pending in
                OTPVerificationSheet(viewModel: viewModel, pending: pending)
            }
            .sheet(item: $viewModel.pendingEmailVerification) { pending in
                EmailVerificationSheet(viewModel: viewModel, pending: pending)
            }
        }
    }
}

// MARK: - Subviews & Sheets

private struct BannerView: View {
    let banner: SignInViewModel.Banner
    
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

private struct OTPVerificationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SignInViewModel
    let pending: SignInViewModel.PendingOTP
    
    @State private var otpCode: String = ""
    @FocusState private var focusedField: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.secondaryBackground.ignoresSafeArea()
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("二階段驗證")
                            .font(.displaySmall)
                            .foregroundColor(.textPrimary)
                        Text("請輸入認證 App 顯示的 6 碼數字")
                            .font(.bodyMedium)
                            .foregroundColor(.textSecondary)
                    }
                    .padding(.top, 32)
                    
                    // Custom OTP Input
                    HStack(spacing: 12) {
                        ForEach(0..<6, id: \.self) { index in
                            let char = index < otpCode.count ? String(Array(otpCode)[index]) : ""
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(focusedField && index == otpCode.count ? Color.primaryBrand : Color.border, lineWidth: 1.5)
                                    )
                                Text(char)
                                    .font(.title2.monospaced())
                                    .foregroundColor(.textPrimary)
                            }
                            .frame(height: 56)
                        }
                    }
                    .background(
                        TextField("", text: $otpCode)
                            .keyboardType(.numberPad)
                            .focused($focusedField)
                            .opacity(0.01) // Invisible but captures input
                            .onChange(of: otpCode) { newValue in
                                if newValue.count > 6 { otpCode = String(newValue.prefix(6)) }
                            }
                    )
                    .onTapGesture { focusedField = true }
                    
                    PrimaryButton("驗證", isLoading: viewModel.isVerifyingOTP, isDisabled: otpCode.count != 6) {
                        Task {
                            let result = await viewModel.completeOTP(otpCode: otpCode)
                            if case .success = result { dismiss() }
                        }
                    }
                    
                    Spacer()
                }
                .padding(24)
            }
            .onAppear { focusedField = true }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

private struct EmailVerificationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SignInViewModel
    let pending: SignInViewModel.PendingEmailVerification
    
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
                        Text("已發送驗證碼至 \(pending.displayEmail)")
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
final class SignInViewModel: ObservableObject {
    enum Field: Hashable {
        case email
        case password
    }

    struct Banner: Identifiable, Equatable {
        enum Kind { case success, error }
        let id = UUID()
        let title: String
        let message: String
        let kind: Kind
    }

    struct PendingOTP: Identifiable, Equatable {
        let id = UUID()
        let email: String
        let password: String
    }

    struct PendingEmailVerification: Identifiable, Equatable {
        let id = UUID()
        let context: AuthManager.EmailVerificationContext
        let displayEmail: String
    }

    enum OTPFlowError: LocalizedError {
        case missingContext

        var errorDescription: String? {
            switch self {
            case .missingContext:
                return "驗證流程已過期，請重新登入"
            }
        }
    }

    enum EmailVerificationFlowError: LocalizedError {
        case missingContext

        var errorDescription: String? {
            switch self {
            case .missingContext:
                return "驗證流程已過期，請重新登入"
            }
        }
    }

    @Published var email: String = ""
    @Published var password: String = ""
    @Published var isPasswordVisible: Bool = false
    @Published var isSubmitting: Bool = false
    @Published var banner: Banner?
    @Published var pendingOTP: PendingOTP?
    @Published var isVerifyingOTP: Bool = false
    @Published var pendingEmailVerification: PendingEmailVerification?
    @Published var isVerifyingEmail: Bool = false
    @Published var isResendingEmailCode: Bool = false

    private var bannerDismissTask: Task<Void, Never>?

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPassword: String {
        password.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmailValid: Bool {
        let regex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: trimmedEmail)
    }

    var isPasswordValid: Bool {
        !trimmedPassword.isEmpty
    }

    @Published var emailValidated: Bool = false

    var shouldShowPasswordError: Bool {
        !password.isEmpty && !isPasswordValid
    }

    var emailErrorMessage: String? {
        (emailValidated && !isEmailValid) ? "請輸入有效的 Email 格式" : nil
    }

    var passwordErrorMessage: String? {
        shouldShowPasswordError ? "密碼不可為空" : nil
    }

    var canSubmit: Bool {
        isEmailValid && isPasswordValid && !isSubmitting
    }

    func submit() async {
        guard canSubmit else {
            if !isEmailValid {
                showBanner(title: "無效的 Email", message: "請確認電子郵件格式是否正確", kind: .error)
            } else if !isPasswordValid {
                showBanner(title: "請輸入密碼", message: "登入需要您的帳號密碼", kind: .error)
            }
            return
        }
        
        isSubmitting = true
        defer { isSubmitting = false }
        
        do {
            _ = try await AuthManager.shared.signIn(email: trimmedEmail, password: trimmedPassword)
            // 成功：AuthManager 會更新狀態，這裡無需額外處理
        } catch let error as AuthManager.SignInError {
            switch error {
            case .otpRequired(let email, let password):
                pendingOTP = PendingOTP(email: email, password: password)
            case .emailVerificationRequired(let context):
                pendingEmailVerification = PendingEmailVerification(context: context, displayEmail: trimmedEmail)
            }
        } catch {
            showBanner(title: "登入失敗", message: error.localizedDescription, kind: .error)
        }
    }
    
    func completeOTP(otpCode: String) async -> Result<Void, Error> {
        guard let pending = pendingOTP else { return .failure(OTPFlowError.missingContext) }
        
        isVerifyingOTP = true
        defer { isVerifyingOTP = false }
        
        do {
            _ = try await AuthManager.shared.signInWithOTP(email: pending.email, password: pending.password, otpCode: otpCode)
            pendingOTP = nil
            return .success(())
        } catch {
            showBanner(title: "驗證失敗", message: error.localizedDescription, kind: .error)
            return .failure(error)
        }
    }
    
    func completeEmailVerification(code: String) async -> Result<Void, Error> {
        guard let pending = pendingEmailVerification else { return .failure(EmailVerificationFlowError.missingContext) }
        
        isVerifyingEmail = true
        defer { isVerifyingEmail = false }
        
        do {
            _ = try await AuthManager.shared.verifyEmail(context: pending.context, code: code)
            pendingEmailVerification = nil
            showBanner(title: "驗證成功", message: "請嘗試重新登入", kind: .success)
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
             showBanner(title: "已發送", message: "新的驗證碼已寄出", kind: .success)
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
