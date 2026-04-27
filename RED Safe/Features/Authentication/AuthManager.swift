import Foundation
import Security

// MARK: - Keychain Utility

/// KeychainHelper 專職封裝敏感資訊的讀寫，遵循單一職責原則確保安全性元件集中管理。
enum KeychainHelper {
    @discardableResult
    static func save(key: String, data: Data) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            return result as? Data
        }
        return nil
    }

    static func loadString(key: String) -> String? {
        guard let data = load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func saveString(_ value: String, for key: String) {
        save(key: key, data: Data(value.utf8))
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Authentication Store

/// AuthManager 作為認證領域的唯一協調者，負責狀態生命週期、Token 管理與使用者資訊同步 (符合 SRP/OCP)。
@MainActor
final class AuthManager: ObservableObject {
    enum Phase: Equatable {
        case launching
        case refreshing
        case authenticated
        case signedOut
    }

    enum SignInError: LocalizedError {
        case otpRequired(email: String, password: String)
        case emailVerificationRequired(context: EmailVerificationContext)

        var errorDescription: String? {
            switch self {
            case .otpRequired:
                return "此帳號已啟用二階段驗證，請輸入 OTP 驗證碼"
            case .emailVerificationRequired:
                return "信箱尚未認證，請輸入寄送到 Email 的 6 碼驗證碼"
            }
        }
    }

    struct UserProfile: Equatable {
        var email: String
        var displayName: String
        var otpEnabled: Bool

        func renamed(_ name: String) -> UserProfile {
            var copy = self
            copy.displayName = name
            return copy
        }

        func withOtpEnabled(_ enabled: Bool) -> UserProfile {
            var copy = self
            copy.otpEnabled = enabled
            return copy
        }
    }

    struct EmailVerificationContext: Equatable {
        let email: String
        let password: String
        let userId: String
    }

    static let shared = AuthManager()

    @Published private(set) var phase: Phase = .launching
    @Published private(set) var profile: UserProfile?
    @Published private(set) var isWorking: Bool = false
    @Published private(set) var lastErrorDescription: String?

    var accessToken: String? { tokens?.accessToken }
    var isLoggedIn: Bool { phase == .authenticated }
    var userName: String? { profile?.displayName }

    private struct SessionTokens {
        var accessToken: String
        var refreshToken: String
    }

    private var tokens: SessionTokens?

    private let refreshKey = "refreshtoken"
    private let usernameKey = "username"
    private let emailKey = "email"
    private let otpEnabledKey = "otp_enabled"

    private init() {}

    // MARK: - Lifecycle

    /// 初始化時觸發自動登入流程，確保 App 啟動體驗一致。
    func bootstrap() {
        guard phase == .launching else { return }
        Task { await restoreSessionIfPossible() }
    }

    @discardableResult
    /// 嘗試透過 Refresh Token 還原會話；若失敗則回復到登出狀態。
    /// 暫時性網路錯誤不會登出使用者，僅記錄錯誤描述。
    func restoreSessionIfPossible() async -> Bool {
        phase = .refreshing
        guard let refresh = storedRefreshToken else {
            tokens = nil
            profile = nil
            phase = .signedOut
            return false
        }

        do {
            let access = try await retryRefresh(refreshToken: refresh)
            tokens = SessionTokens(accessToken: access, refreshToken: refresh)
            if await refreshProfileFromRemote(force: true) == nil {
                hydrateProfileIfNeeded()
            }
            phase = .authenticated
            return true
        } catch where isDefinitiveAuthFailure(error) {
            clearPersistedSession()
            phase = .signedOut
            lastErrorDescription = error.localizedDescription
            return false
        } catch {
            // 暫時性網路錯誤：保留 refresh token，不登出
            hydrateProfileIfNeeded()
            phase = .signedOut
            lastErrorDescription = "網路連線不穩定，請稍後再試"
            return false
        }
    }

    // MARK: - Auth Flows

    @discardableResult
    /// 驗證帳密並建立全新會話，成功後回傳使用者檔案。
    func signIn(email: String, password: String) async throws -> UserProfile {
        isWorking = true
        defer { isWorking = false }

        let response = try await APIClient.shared.signIn(email: email, password: password)
        if response.requiresEmailVerification {
            let context = try await prepareEmailVerificationContext(email: email, password: password)
            throw SignInError.emailVerificationRequired(context: context)
        }
        if response.requiresOTP {
            throw SignInError.otpRequired(email: email, password: password)
        }

        return try await finalizeSignIn(with: response, email: email)
    }

    @discardableResult
    func signInWithOTP(email: String, password: String, otpCode: String?) async throws -> UserProfile {
        isWorking = true
        defer { isWorking = false }

        let response = try await APIClient.shared.signInWithOTP(email: email, password: password, otpCode: otpCode)
        if response.requiresEmailVerification {
            let context = try await prepareEmailVerificationContext(email: email, password: password)
            throw SignInError.emailVerificationRequired(context: context)
        }
        if response.requiresOTP {
            throw ApiError.invalidPayload(reason: "伺服器回傳要求再次輸入 OTP，請稍後再試")
        }
        return try await finalizeSignIn(with: response, email: email)
    }

    func resendEmailVerification(for context: EmailVerificationContext) async throws {
        _ = try await APIClient.shared.requestEmailVerification(userId: context.userId)
    }

    func verifyEmail(context: EmailVerificationContext, code: String) async throws -> UserProfile {
        _ = try await APIClient.shared.verifyEmail(userId: context.userId, code: code)
        return try await signIn(email: context.email, password: context.password)
    }

    @discardableResult
    /// 透過 Refresh Token 續期 Access Token，維持登入狀態。
    /// 暫時性網路錯誤會重試，不會直接登出使用者。
    func refreshAccessToken(refreshToken: String? = nil) async -> Bool {
        let refresh = refreshToken ?? tokens?.refreshToken ?? storedRefreshToken
        guard let refresh, !refresh.isEmpty else {
            tokens = nil
            profile = nil
            phase = .signedOut
            return false
        }

        do {
            let access = try await retryRefresh(refreshToken: refresh)

            if tokens != nil {
                tokens?.accessToken = access
                tokens?.refreshToken = refresh
            } else {
                tokens = SessionTokens(accessToken: access, refreshToken: refresh)
            }

            if await refreshProfileFromRemote(force: true) == nil {
                hydrateProfileIfNeeded()
            }
            phase = .authenticated
            return true
        } catch where isDefinitiveAuthFailure(error) {
            clearPersistedSession()
            phase = .signedOut
            lastErrorDescription = error.localizedDescription
            return false
        } catch {
            // 暫時性網路錯誤：保留 refresh token，不登出
            lastErrorDescription = "網路連線不穩定，請稍後再試"
            return false
        }
    }

    // MARK: - Resilient Refresh Helpers

    /// 嘗試以指數退避重試 refresh，最多 3 次。回傳新的 access token。
    /// 使用 nonisolated 避免在 @MainActor 上 sleep 阻塞 UI。
    private nonisolated func retryRefresh(refreshToken: String, maxAttempts: Int = 3) async throws -> String {
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                let response = try await APIClient.shared.refreshAccessToken(refreshToken: refreshToken)
                guard !response.accessToken.isEmpty else {
                    throw ApiError.invalidPayload(reason: "伺服器未回傳 access token")
                }
                return response.accessToken
            } catch {
                if await isDefinitiveAuthFailure(error) { throw error }
                lastError = error
                if attempt < maxAttempts {
                    if await !NetworkMonitor.shared.isConnected {
                        let recovered = await NetworkMonitor.shared.waitForConnectivity(timeout: 15)
                        if !recovered { break }
                    }
                    let baseDelay = pow(2.0, Double(attempt - 1))
                    let jitter = Double.random(in: 0.8...1.2)
                    let delay = baseDelay * jitter
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        throw lastError ?? ApiError.transport(URLError(.notConnectedToInternet))
    }

    /// 判斷錯誤是否為伺服器明確拒絕（非暫時性），應立即登出。
    private func isDefinitiveAuthFailure(_ error: Error) -> Bool {
        guard let apiError = error as? ApiError else { return false }
        switch apiError {
        case .http(let status, let code, _, _):
            if let code, ["132", "127"].contains(code.rawValue) { return true }
            return (400...499).contains(status)
        case .invalidPayload:
            return true
        default:
            return false
        }
    }

    /// 手動登出並清除本地憑證。
    func signOut() {
        tokens = nil
        profile = nil
        clearPersistedSession()
        phase = .signedOut
    }

    private func prepareEmailVerificationContext(email: String, password: String) async throws -> EmailVerificationContext {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let lookupEmail = trimmedEmail.lowercased()
        let userId = try await APIClient.shared.lookupUserId(by: lookupEmail)
        _ = try await APIClient.shared.requestEmailVerification(userId: userId)
        return EmailVerificationContext(email: trimmedEmail, password: password, userId: userId)
    }

    private func finalizeSignIn(with response: SignInResponse, email: String) async throws -> UserProfile {
#if DEBUG
        print("🔐 SignInResponse debug userName=\(response.userName ?? "nil") access=\(response.accessToken ?? "<nil>") refresh=\(response.refreshToken ?? "<nil>")")
#endif
        guard let access = response.accessToken, !access.isEmpty else {
            throw ApiError.invalidPayload(reason: "伺服器未回傳 access token")
        }
        guard let refresh = response.refreshToken, !refresh.isEmpty else {
            throw ApiError.invalidPayload(reason: "伺服器未回傳 refresh token")
        }

        let resolvedName = response.normalizedUserName ?? email
        let fallbackProfile = UserProfile(email: email, displayName: resolvedName, otpEnabled: false)

        persistSession(refreshToken: refresh, displayName: resolvedName, email: email, otpEnabled: fallbackProfile.otpEnabled)
        tokens = SessionTokens(accessToken: access, refreshToken: refresh)

        if let remoteProfile = await refreshProfileFromRemote(force: true) {
            phase = .authenticated
            return remoteProfile
        } else {
            self.profile = fallbackProfile
            phase = .authenticated
            return fallbackProfile
        }
    }

    @discardableResult
    /// 更新顯示名稱並同步 Keychain 中的快取。
    func updateUserName(to newName: String) async throws -> ApiErrorCode {
        let result = try await APIClient.shared.updateUserName(newName)
        KeychainHelper.saveString(newName, for: usernameKey)
        if let current = profile {
            let updated = current.renamed(newName)
            profile = updated
            if let session = tokens {
                persistSession(
                    refreshToken: session.refreshToken,
                    displayName: updated.displayName,
                    email: updated.email,
                    otpEnabled: updated.otpEnabled
                )
            }
        }
        return result
    }

    // MARK: - Helpers

    @discardableResult
    func refreshProfileFromRemote(force: Bool = false) async -> UserProfile? {
        guard let session = tokens, force || !session.accessToken.isEmpty else { return nil }
        do {
            let response = try await APIClient.shared.fetchUserInfo()
            let normalizedEmail = normalize(response.email) ?? profile?.email ?? ""
            let fallbackName = normalize(profile?.displayName)
            let normalizedName = normalize(response.userName)
                ?? fallbackName
                ?? (normalizedEmail.isEmpty ? "使用者" : normalizedEmail)
            let resolvedProfile = UserProfile(
                email: normalizedEmail,
                displayName: normalizedName,
                otpEnabled: response.otpEnabled
            )
            persistSession(
                refreshToken: session.refreshToken,
                displayName: resolvedProfile.displayName,
                email: resolvedProfile.email,
                otpEnabled: resolvedProfile.otpEnabled
            )
            profile = resolvedProfile
            return resolvedProfile
        } catch {
            lastErrorDescription = error.localizedDescription
            return nil
        }
    }

    private var storedRefreshToken: String? {
        KeychainHelper.loadString(key: refreshKey)
    }

    private func hydrateProfileIfNeeded() {
        guard profile == nil else { return }
        let storedName = normalize(KeychainHelper.loadString(key: usernameKey))
        let storedEmail = normalize(KeychainHelper.loadString(key: emailKey)) ?? ""
        let otpFlag = KeychainHelper.loadString(key: otpEnabledKey)?.lowercased()
        let otpEnabled = otpFlag == "1" || otpFlag == "true"
        let resolvedName = storedName ?? (storedEmail.isEmpty ? "使用者" : storedEmail)
        profile = UserProfile(email: storedEmail, displayName: resolvedName, otpEnabled: otpEnabled)
    }

    private func persistSession(refreshToken: String, displayName: String, email: String, otpEnabled: Bool) {
        KeychainHelper.saveString(refreshToken, for: refreshKey)
        KeychainHelper.saveString(displayName, for: usernameKey)
        KeychainHelper.saveString(email, for: emailKey)
        KeychainHelper.saveString(otpEnabled ? "1" : "0", for: otpEnabledKey)
    }

    private func clearPersistedSession() {
        KeychainHelper.delete(key: refreshKey)
        KeychainHelper.delete(key: usernameKey)
        KeychainHelper.delete(key: emailKey)
        KeychainHelper.delete(key: otpEnabledKey)
    }

    private func normalize(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
