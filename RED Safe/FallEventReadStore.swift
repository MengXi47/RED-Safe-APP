import Foundation
import Observation

// MARK: - Fall Event Read Store

/// 跌倒事件「已讀/未讀」狀態的本地儲存，UserDefaults 作為持久層。
///
/// 設計選型:
/// - 使用單例 `@MainActor @Observable` 包裝,讓 SwiftUI 視圖可在不需要顯式重新查詢
///   的情況下,於詳情頁標記已讀後立即更新列表的紅點/加粗樣式。
/// - UserDefaults key 採 `fall_read_<eventId>` 一筆一鍵,避免讀寫單一大型 dictionary
///   時的競態風險,且在資料量極大(數萬筆)前 UserDefaults 仍能穩定運作。
/// - `static` API 為呼叫端方便包裝;狀態變更仍會透過內部 shared 實例通知 SwiftUI。
@MainActor
@Observable
final class FallEventReadStore {
    static let shared = FallEventReadStore()

    /// UserDefaults key prefix。修改此常數會讓所有既有已讀紀錄失效,請勿輕易變更。
    private static let keyPrefix = "fall_read_"

    /// 已讀事件 id 的快取;以 Set 操作降低查詢成本,並讓 SwiftUI 觀察單一屬性即可全面感知變動。
    private(set) var readIds: Set<String>

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.readIds = Self.loadAll(from: defaults)
    }

    // MARK: - Public Static API

    static func isRead(_ eventId: String) -> Bool {
        shared.readIds.contains(eventId)
    }

    static func markRead(_ eventId: String) {
        shared.markReadInternal(eventId)
    }

    /// 批次標記已讀,適用於「全部標已讀」按鈕。重複 id 與已讀 id 會被去重略過。
    static func markAllRead(_ ids: [String]) {
        shared.markAllReadInternal(ids)
    }

    // MARK: - Internal Mutation

    private func markReadInternal(_ eventId: String) {
        guard !readIds.contains(eventId) else { return }
        readIds.insert(eventId)
        defaults.set(true, forKey: Self.key(for: eventId))
    }

    private func markAllReadInternal(_ ids: [String]) {
        let newOnes = ids.filter { !readIds.contains($0) }
        guard !newOnes.isEmpty else { return }
        readIds.formUnion(newOnes)
        for id in newOnes {
            defaults.set(true, forKey: Self.key(for: id))
        }
    }

    // MARK: - Helpers

    private static func key(for eventId: String) -> String {
        keyPrefix + eventId
    }

    /// 從 UserDefaults 載入所有已讀紀錄;掃描所有 keys 以還原 Set 狀態。
    /// UserDefaults `dictionaryRepresentation()` 在 iOS 上是 O(n) 但只在 init 執行一次,
    /// 對使用者規模可接受。
    private static func loadAll(from defaults: UserDefaults) -> Set<String> {
        let snapshot = defaults.dictionaryRepresentation()
        var ids: Set<String> = []
        for (key, value) in snapshot where key.hasPrefix(keyPrefix) {
            // 僅接受 true 值,避免歷史 false 殘留汙染。
            if let flag = value as? Bool, flag {
                ids.insert(String(key.dropFirst(keyPrefix.count)))
            }
        }
        return ids
    }
}
