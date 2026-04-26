import SwiftUI
import UIKit

/// AsyncImage 的薄包裝：載圖時自帶 `Authorization: Bearer <JWT>`，
/// 適用於跌倒事件快照等需要 token 認證的私密影像端點。
///
/// 設計原則：
/// - 視覺呈現上盡量貼齊既有設計系統（surface/border/textTertiary）。
/// - 載入失敗或無圖時退回到 placeholder，永不顯示破圖。
/// - 走 APIClient.fetchAuthenticatedData(url:) 統一路徑，自動處理 401 → refresh → retry。
/// - 命中 FallSnapshotImageCache 時直接顯示，跨 view 共用降載。
struct AuthenticatedAsyncImage<Placeholder: View>: View {
    let url: URL?
    /// 可選的版本鍵：當同一 URL 物件因外部狀態改變需要重新載入時可帶入新值觸發重抓；
    /// 同時也作為 image cache key 的 stable identity 來源（避免 query string 抖動造成 miss）。
    var cacheKey: String?
    var contentMode: ContentMode = .fill
    /// 給輔助科技用的描述（VoiceOver）。預設 nil 表示使用系統預設。
    var accessibilityLabel: String?
    let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var didFail = false

    init(
        url: URL?,
        cacheKey: String? = nil,
        contentMode: ContentMode = .fill,
        accessibilityLabel: String? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.cacheKey = cacheKey
        self.contentMode = contentMode
        self.accessibilityLabel = accessibilityLabel
        self.placeholder = placeholder
    }

    var body: some View {
        ZStack {
            if let image {
                imageView(image)
            } else if didFail {
                placeholder()
            } else if isLoading {
                placeholder()
                    .overlay(ProgressView().tint(Color.textSecondary))
            } else {
                placeholder()
            }
        }
        .task(id: taskIdentity) {
            await loadIfNeeded()
        }
    }

    @ViewBuilder
    private func imageView(_ image: UIImage) -> some View {
        let view = Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: contentMode)
        if let accessibilityLabel {
            view.accessibilityLabel(Text(accessibilityLabel))
        } else {
            view
        }
    }

    private var taskIdentity: String {
        (url?.absoluteString ?? "<nil>") + "::" + (cacheKey ?? "")
    }

    private var resolvedCacheKey: String? {
        cacheKey ?? url?.absoluteString
    }

    private func loadIfNeeded() async {
        guard let url else {
#if DEBUG
            print("🖼️ [AAI] task fired but url=nil (cacheKey=\(cacheKey ?? "<nil>"))")
#endif
            didFail = true
            return
        }
        guard !isLoading, image == nil else {
#if DEBUG
            print("🖼️ [AAI] skip (isLoading=\(isLoading), hasImage=\(image != nil)) ← \(url.absoluteString)")
#endif
            return
        }

        // 先查記憶體快取
        if let key = resolvedCacheKey,
           let cached = await FallSnapshotImageCache.shared.image(for: key) {
#if DEBUG
            print("🖼️ [AAI] cache hit key=\(key) ← \(url.absoluteString)")
#endif
            image = cached
            return
        }

        isLoading = true
        didFail = false
        defer { isLoading = false }

        do {
            let data = try await APIClient.shared.fetchAuthenticatedData(url: url)
            guard let decoded = UIImage(data: data) else {
#if DEBUG
                print("🖼️ [AAI] UIImage decode FAILED (\(data.count) bytes) ← \(url.absoluteString)")
#endif
                didFail = true
                return
            }
            image = decoded
            if let key = resolvedCacheKey {
                await FallSnapshotImageCache.shared.set(decoded, for: key)
            }
        } catch {
#if DEBUG
            print("🖼️ [AAI] fetch FAILED ← \(url.absoluteString): \(error)")
#endif
            didFail = true
        }
    }
}

extension AuthenticatedAsyncImage where Placeholder == DefaultAuthenticatedImagePlaceholder {
    init(
        url: URL?,
        cacheKey: String? = nil,
        contentMode: ContentMode = .fill,
        accessibilityLabel: String? = nil
    ) {
        self.init(
            url: url,
            cacheKey: cacheKey,
            contentMode: contentMode,
            accessibilityLabel: accessibilityLabel,
            placeholder: { DefaultAuthenticatedImagePlaceholder() }
        )
    }
}

/// 預設 placeholder：與 GlassContainer 相同的 surface 色 + 半透明圖示，避免破圖視覺。
struct DefaultAuthenticatedImagePlaceholder: View {
    var body: some View {
        Rectangle()
            .fill(Color.surface)
            .overlay(
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(Color.textTertiary)
            )
    }
}
