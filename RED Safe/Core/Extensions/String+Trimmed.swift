import Foundation

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 修剪頭尾空白後若仍非空則返回字串，否則返回 nil。
    /// 適用於 `value?.nonEmpty ?? "—"` 這類後備鏈。
    var nonEmpty: String? {
        let result = trimmed
        return result.isEmpty ? nil : result
    }
}
