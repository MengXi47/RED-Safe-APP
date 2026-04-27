import Foundation

// MARK: - Shared display formatters

/// 全 App 顯示給使用者的時間統一以 `Asia/Taipei` 呈現,
/// 避免不同頁面落在 UTC 或裝置 system default 而出現「時差錯亂」的視覺問題。
///
/// 注意:此 extension 僅處理「給使用者看」的時間。傳給 backend 的 ISO-8601 字串
/// 仍保留 UTC offset(由 Codable 預設 `.iso8601` 策略處理),不在此處轉換。
@MainActor
enum RedSafeDateFormatter {
    /// 主要時區常數;集中於此檔以便日後若需 i18n 時統一替換。
    static let displayTimeZone: TimeZone = TimeZone(identifier: "Asia/Taipei") ?? .current

    /// 列表/詳情共用的「年/月/日 時:分」絕對時間格式,例如 `2026/04/27 13:45`。
    static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.timeZone = displayTimeZone
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f
    }()

    /// 後端常見 ISO-8601 帶毫秒的解析器。
    static let isoParserWithMs: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// 後端 ISO-8601 不帶毫秒的解析器。fallback 用。
    static let isoParserNoMs: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// 容忍兩種 ISO-8601 格式;解析失敗則回傳 nil。
    static func parseISO(_ iso: String) -> Date? {
        if let d = isoParserWithMs.date(from: iso) { return d }
        return isoParserNoMs.date(from: iso)
    }

    /// 將後端 ISO-8601 時間字串渲染為台北時間的 `yyyy/MM/dd HH:mm`。
    /// 解析失敗時回傳 fallback(預設 `—`);呼叫端需自行決定空字串保留與否。
    static func displayAbsolute(from iso: String?, fallback: String = "—") -> String {
        guard let iso, !iso.isEmpty else { return fallback }
        guard let date = parseISO(iso) else { return iso }
        return absoluteFormatter.string(from: date)
    }
}
