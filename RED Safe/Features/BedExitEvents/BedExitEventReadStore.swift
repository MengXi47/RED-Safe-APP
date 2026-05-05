import Foundation
import Observation

// MARK: - Bed Exit Event Read Store

/// 夜間離床事件「已讀/未讀」狀態的本地儲存,設計與 `InactivityEventReadStore` 一致。
///
/// key prefix 採 `bed_exit_read_` 與 fall / inactivity 隔離,避免不同事件類別的已讀狀態混雜。
@MainActor
@Observable
final class BedExitEventReadStore {
    static let shared = BedExitEventReadStore()

    private static let keyPrefix = "bed_exit_read_"

    private(set) var readIds: Set<String>

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.readIds = Self.loadAll(from: defaults)
    }

    static func isRead(_ eventId: String) -> Bool {
        shared.readIds.contains(eventId)
    }

    static func markRead(_ eventId: String) {
        shared.markReadInternal(eventId)
    }

    static func markAllRead(_ ids: [String]) {
        shared.markAllReadInternal(ids)
    }

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

    private static func key(for eventId: String) -> String {
        keyPrefix + eventId
    }

    private static func loadAll(from defaults: UserDefaults) -> Set<String> {
        let snapshot = defaults.dictionaryRepresentation()
        var ids: Set<String> = []
        for (key, value) in snapshot where key.hasPrefix(keyPrefix) {
            if let flag = value as? Bool, flag {
                ids.insert(String(key.dropFirst(keyPrefix.count)))
            }
        }
        return ids
    }
}
