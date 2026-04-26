import UIKit

/// 跨 view 共享的記憶體影像快取，避免使用者在列表 ↔ 詳情間切換時重複下載相同快照。
///
/// 採用 actor 包 NSCache 兼顧執行緒安全與系統低記憶體自動釋放：
/// - NSCache 在系統記憶體告急時會自動驅逐物件
/// - actor 隔離保證 get/set 序列化，避免 cache stampede
final actor FallSnapshotImageCache {
    static let shared = FallSnapshotImageCache()

    private let storage: NSCache<NSString, UIImage>

    init(countLimit: Int = 120, totalCostLimit: Int = 64 * 1024 * 1024) {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
        self.storage = cache
    }

    func image(for key: String) -> UIImage? {
        storage.object(forKey: key as NSString)
    }

    func set(_ image: UIImage, for key: String) {
        // cost 大致等於 byte 數（4 bytes/pixel），讓 NSCache 在 totalCostLimit 下自動 evict。
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        storage.setObject(image, forKey: key as NSString, cost: cost)
    }

    func clear() {
        storage.removeAllObjects()
    }
}
