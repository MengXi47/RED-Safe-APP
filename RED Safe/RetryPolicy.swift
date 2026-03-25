import Foundation

// MARK: - Retry Policy

/// 定義 API 請求的重試策略，含最大次數、指數退避延遲與抖動範圍。
struct RetryPolicy: Sendable {
    /// 最大嘗試次數（含首次請求）。
    let maxAttempts: Int
    /// 第一次重試的基礎延遲（秒）。
    let baseDelay: TimeInterval
    /// 延遲上限（秒）。
    let maxDelay: TimeInterval
    /// 抖動係數範圍，避免多請求同時重試造成雷群效應。
    let jitterRange: ClosedRange<Double>

    /// 一般 authenticated API 呼叫。
    static let `default` = RetryPolicy(
        maxAttempts: 3,
        baseDelay: 1.0,
        maxDelay: 15.0,
        jitterRange: 0.8...1.2
    )

    /// 關鍵操作（綁定裝置、啟用授權等）。
    static let aggressive = RetryPolicy(
        maxAttempts: 5,
        baseDelay: 0.5,
        maxDelay: 30.0,
        jitterRange: 0.7...1.3
    )

    /// 不重試（登入、註冊等需即時回饋的操作）。
    static let none = RetryPolicy(
        maxAttempts: 1,
        baseDelay: 0,
        maxDelay: 0,
        jitterRange: 1.0...1.0
    )

    /// SSE 輪詢預設策略。
    static let sse = RetryPolicy(
        maxAttempts: 2,
        baseDelay: 2.0,
        maxDelay: 10.0,
        jitterRange: 0.8...1.2
    )
}

// MARK: - Retry Decision

enum RetryDecision {
    case retry(after: TimeInterval)
    case doNotRetry
}

// MARK: - Error Classification

extension RetryPolicy {
    /// 根據錯誤類型與當前嘗試次數決定是否重試。
    func decision(for error: Error, attempt: Int) -> RetryDecision {
        guard attempt < maxAttempts else { return .doNotRetry }
        guard Self.isRetryableError(error) else { return .doNotRetry }

        let exponentialDelay = baseDelay * pow(2.0, Double(attempt - 1))
        let jitter = Double.random(in: jitterRange)
        let delay = min(exponentialDelay * jitter, maxDelay)

        return .retry(after: delay)
    }

    /// 判斷錯誤是否為暫時性、可重試的。
    static func isRetryableError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return retryableURLErrorCodes.contains(urlError.code)
        }

        if let apiError = error as? ApiError {
            switch apiError {
            case .transport(let underlying):
                return isRetryableError(underlying)
            case .http(let status, let code, _, _):
                if code?.rawValue == "126" { return false }
                return retryableHTTPStatusCodes.contains(status)
            case .missingToken, .invalidURL, .decoding, .invalidPayload:
                return false
            }
        }

        return false
    }
}

private let retryableURLErrorCodes: Set<URLError.Code> = [
    .timedOut,
    .notConnectedToInternet,
    .networkConnectionLost,
    .dnsLookupFailed,
    .cannotFindHost,
    .cannotConnectToHost,
    .dataNotAllowed
]

private let retryableHTTPStatusCodes: Set<Int> = [
    500, 502, 503, 504
]
