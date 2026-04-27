import SwiftUI

// MARK: - Event Type Visual Mapping

/// 事件類型的視覺語彙：與 backend EmailService 三色嚴格對齊，整套產品保持一致語境。
enum FallEventTypeStyle {
    case confirmed      // FALL_CONFIRMED  → 紅色 #d92d20
    case recovered      // FALL_RECOVERED  → 綠色 #0e9384
    case selfRecovered  // FALL_SELF_RECOVERED → 灰色 #475467

    init(rawValue: String) {
        switch rawValue.uppercased() {
        case "FALL_CONFIRMED":      self = .confirmed
        case "FALL_RECOVERED":      self = .recovered
        case "FALL_SELF_RECOVERED": self = .selfRecovered
        default:                    self = .selfRecovered
        }
    }

    var color: Color {
        switch self {
        case .confirmed:     return Color(red: 0xD9 / 255, green: 0x2D / 255, blue: 0x20 / 255)
        case .recovered:     return Color(red: 0x0E / 255, green: 0x93 / 255, blue: 0x84 / 255)
        case .selfRecovered: return Color(red: 0x47 / 255, green: 0x54 / 255, blue: 0x67 / 255)
        }
    }

    var label: String {
        switch self {
        case .confirmed:     return "警報"
        case .recovered:     return "已恢復"
        case .selfRecovered: return "自行恢復"
        }
    }

    var icon: String {
        switch self {
        case .confirmed:     return "exclamationmark.triangle.fill"
        case .recovered:     return "checkmark.seal.fill"
        case .selfRecovered: return "figure.walk"
        }
    }
}

// MARK: - Date Formatters

@MainActor
enum FallEventDateFormat {
    /// 後端 ISO-8601；同時容忍是否帶毫秒。
    static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoParserNoMs: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f
    }()

    static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.unitsStyle = .short
        return f
    }()

    static func parse(_ iso: String) -> Date? {
        if let date = isoParser.date(from: iso) { return date }
        return isoParserNoMs.date(from: iso)
    }

    static func displayPair(for iso: String, now: Date = Date()) -> (relative: String, absolute: String) {
        guard let date = parse(iso) else { return ("—", iso) }
        let relative = relativeFormatter.localizedString(for: date, relativeTo: now)
        let absolute = absoluteFormatter.string(from: date)
        return (relative, absolute)
    }
}

// MARK: - View

/// 跌倒事件歷史列表頁。
/// 設計參考 DashboardView / DeviceDetailView：GlassContainer + 既有設計 token，
/// 三事件配色與 backend EmailService 嚴格對齊。
struct FallEventHistoryView: View {
    let edge: EdgeSummary

    @State private var events: [FallEventSummary] = []
    @State private var loadedEventIds: Set<String> = []
    @State private var currentPage: Int = 0
    @State private var totalCount: Int = 0
    @State private var hasMore: Bool = true
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var hasLoadedOnce = false
    @State private var loadError: String?
    @State private var loadMoreError: String?
    @State private var filter: EventFilter = .all

    /// 觀察 shared 已讀狀態,讓詳情頁標記後列表的紅點可即時消失。
    @State private var readStore = FallEventReadStore.shared

    /// 事件類型篩選；UI 只在後端資料載入後依分類顯示。
    enum EventFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case confirmed = "警報"
        case recovered = "已恢復"
        case selfRecovered = "自行恢復"

        var id: String { rawValue }

        func matches(_ event: FallEventSummary) -> Bool {
            switch self {
            case .all:           return true
            case .confirmed:     return event.eventType.uppercased() == "FALL_CONFIRMED"
            case .recovered:     return event.eventType.uppercased() == "FALL_RECOVERED"
            case .selfRecovered: return event.eventType.uppercased() == "FALL_SELF_RECOVERED"
            }
        }
    }

    private let pageSize = 50

    private var filteredEvents: [FallEventSummary] {
        events.filter { filter.matches($0) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                headerCard
                filterChips
                content
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Color.appBackground)
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("跌倒事件紀錄")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { markAllReadToolbar }
        .task { if !hasLoadedOnce { await reload() } }
        .refreshable { await reload() }
    }

    /// 「全部標已讀」按鈕:目前已載入頁中尚未已讀的事件全數寫入本地。未載入頁不影響。
    @ToolbarContentBuilder
    private var markAllReadToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            let unreadIds = events.filter { !readStore.readIds.contains($0.eventId) }.map(\.eventId)
            Button {
                FallEventReadStore.markAllRead(unreadIds)
            } label: {
                Image(systemName: "checkmark.circle")
                    .accessibilityLabel("全部標為已讀")
            }
            .disabled(unreadIds.isEmpty)
        }
    }

    // MARK: Header

    private var headerCard: some View {
        GlassContainer(padding: 20) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.primaryBrand.opacity(0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.title3)
                        .foregroundStyle(Color.primaryBrand)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text((edge.displayName ?? "").isEmpty ? "未命名裝置" : edge.displayName!)
                        .font(.bodyLarge.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text(edge.edgeId)
                        .font(.captionText.monospaced())
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Text(badgeText)
                    .font(.captionText.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondaryBackground)
                    .clipShape(Capsule())
            }
        }
    }

    /// Badge 文案：在後端 total > 已載筆數時明確告知「N / total 筆」，
    /// 避免使用者誤以為這是完整歷史（client-side 篩選只看當前頁）。
    private var badgeText: String {
        let shown = filteredEvents.count
        if totalCount > events.count {
            return "\(shown) / \(totalCount) 筆"
        }
        return "\(shown) 筆"
    }

    // MARK: Filter

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EventFilter.allCases) { option in
                    let isSelected = filter == option
                    Button {
                        filter = option
                    } label: {
                        Text(option.rawValue)
                            .font(.captionText.weight(.semibold))
                            .foregroundStyle(isSelected ? Color.white : Color.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isSelected ? Color.primaryBrand : Color.surface)
                            .overlay(
                                Capsule().stroke(Color.border, lineWidth: isSelected ? 0 : 1)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: States

    @ViewBuilder
    private var content: some View {
        if (isLoading || !hasLoadedOnce) && events.isEmpty && loadError == nil {
            loadingState
        } else if let loadError, events.isEmpty {
            errorState(message: loadError)
        } else if filteredEvents.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView().tint(Color.primaryBrand)
            Text("載入跌倒事件中…")
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func errorState(message: String) -> some View {
        GlassContainer(padding: 24) {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(Color.errorRed)
                Text("無法載入跌倒事件")
                    .font(.bodyLarge.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(message)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await reload() }
                } label: {
                    Text("重試")
                        .font(.buttonText)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.primaryBrand)
                        .clipShape(Capsule())
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyState: some View {
        GlassContainer(padding: 32) {
            VStack(spacing: 14) {
                Image(systemName: "tray")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Color.textTertiary)
                Text(emptyStateTitle)
                    .font(.bodyLarge.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(emptyStateBody)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// 區分「整體無事件」「篩選後本頁無此類事件」與「整體有更多但本頁無」三種情境，
    /// 讓使用者明確知道這只是最新一頁的快取，不是全域結論。
    private var emptyStateTitle: String {
        if events.isEmpty { return "尚無跌倒事件" }
        return "本頁無此類事件"
    }

    private var emptyStateBody: String {
        if events.isEmpty {
            return "當 Edge 偵測到跌倒後會自動上傳並顯示在此。"
        }
        return "可切換上方篩選查看其他類型事件,或下拉重新整理。"
    }

    private var list: some View {
        LazyVStack(spacing: 16) {
            ForEach(filteredEvents) { event in
                NavigationLink {
                    FallEventDetailView(edgeId: edge.edgeId, eventId: event.eventId)
                } label: {
                    FallEventCard(
                        event: event,
                        edgeId: edge.edgeId,
                        isUnread: !readStore.readIds.contains(event.eventId)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .onAppear {
                    // 觸發條件用「未篩選」清單的最後一筆 eventId,
                    // 避免使用者切換篩選後該分類資料較少而提早卡死無法繼續分頁。
                    if event.eventId == events.last?.eventId {
                        Task { await loadMoreIfNeeded() }
                    }
                }
            }

            listFooter
        }
    }

    @ViewBuilder
    private var listFooter: some View {
        if isLoadingMore {
            HStack(spacing: 10) {
                ProgressView().tint(Color.primaryBrand)
                Text("載入更多事件中…")
                    .font(.captionText)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        } else if let loadMoreError {
            VStack(spacing: 8) {
                Text("載入更多失敗:\(loadMoreError)")
                    .font(.captionText)
                    .foregroundStyle(Color.errorRed)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await loadMoreIfNeeded(force: true) }
                } label: {
                    Text("重試")
                        .font(.captionText.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.primaryBrand)
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else if !hasMore && !events.isEmpty {
            Text("已顯示全部 \(events.count) 筆事件")
                .font(.captionText)
                .foregroundStyle(Color.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
    }

    // MARK: Loading

    /// 重設分頁狀態並重新從 page 0 拉取,供 `.task` 初始化與 `.refreshable` 下拉刷新使用。
    private func reload() async {
        // 並發守衛:.task 與 .refreshable 可能同時觸發,避免雙重請求造成資料閃爍。
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        loadMoreError = nil
        defer {
            isLoading = false
            hasLoadedOnce = true
        }
        do {
            let response = try await APIClient.shared.fetchFallEvents(
                edgeId: edge.edgeId,
                page: 0,
                size: pageSize
            )
            // 重設後一次性覆蓋,避免上一輪殘留資料造成 UI 閃爍。
            events = response.events
            loadedEventIds = Set(response.events.map(\.eventId))
            totalCount = response.total
            currentPage = 0
            hasMore = computeHasMore(loaded: events.count, total: response.total, lastBatch: response.events.count)
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// 載入下一頁。觸發點為列表最後一筆的 onAppear,並由 `currentPage`/`hasMore`/`isLoadingMore` 三者守衛。
    /// `force=true` 用於使用者點擊「重試」時繞過 `loadMoreError` 的暫停狀態。
    private func loadMoreIfNeeded(force: Bool = false) async {
        guard hasLoadedOnce, !isLoading, !isLoadingMore, hasMore else { return }
        guard force || loadMoreError == nil else { return }

        isLoadingMore = true
        loadMoreError = nil
        defer { isLoadingMore = false }

        let nextPage = currentPage + 1
        do {
            let response = try await APIClient.shared.fetchFallEvents(
                edgeId: edge.edgeId,
                page: nextPage,
                size: pageSize
            )
            // 用 Set 去重:後端理論上分頁不重複,但網路重試/競態下偶爾會重複,
            // 為避免 SwiftUI ForEach 因 id 衝突 crash 而以本地 set 為準。
            let newOnes = response.events.filter { !loadedEventIds.contains($0.eventId) }
            events.append(contentsOf: newOnes)
            loadedEventIds.formUnion(newOnes.map(\.eventId))
            totalCount = response.total
            currentPage = nextPage
            hasMore = computeHasMore(loaded: events.count, total: response.total, lastBatch: response.events.count)
        } catch {
            loadMoreError = error.localizedDescription
        }
    }

    /// 判斷是否還有更多頁:後端提供 total 時優先以 total 為準,
    /// 若後端回傳異常(total=0 但仍有資料)則 fallback 用「本批是否已小於 pageSize」推測。
    private func computeHasMore(loaded: Int, total: Int, lastBatch: Int) -> Bool {
        if total > 0 { return loaded < total }
        return lastBatch >= pageSize
    }
}

// MARK: - Card

private struct FallEventCard: View {
    let event: FallEventSummary
    let edgeId: String
    let isUnread: Bool

    var body: some View {
        let style = FallEventTypeStyle(rawValue: event.eventType)
        let displayTime = FallEventDateFormat.displayPair(for: event.eventTime)
        let title = event.cameraCustomName?.nonEmpty ?? event.cameraIp ?? "未知攝影機"

        return GlassContainer(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                thumbnail(style: style)
                metadata(title: title, time: displayTime, style: style)
            }
        }
    }

    private func thumbnail(style: FallEventTypeStyle) -> some View {
        ZStack(alignment: .topTrailing) {
            thumbnailImage
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 6) {
                Image(systemName: style.icon)
                    .font(.captionText)
                Text(style.label)
                    .font(.captionText.weight(.semibold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(style.color)
            .clipShape(Capsule())
            .padding(10)
        }
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let path = event.thumbnailUrl, !path.isEmpty {
            AuthenticatedAsyncImage(
                url: APIClient.shared.fallSnapshotURL(path: path, edgeId: edgeId),
                cacheKey: "thumb-\(event.eventId)",
                contentMode: .fill,
                accessibilityLabel: accessibilityDescription
            )
        } else {
            DefaultAuthenticatedImagePlaceholder()
        }
    }

    private var accessibilityDescription: String {
        let typeLabel = FallEventTypeStyle(rawValue: event.eventType).label
        let camera = event.cameraCustomName?.nonEmpty ?? event.cameraIp ?? "未知攝影機"
        return "\(typeLabel)事件縮圖,\(camera)"
    }

    private func metadata(title: String, time: (relative: String, absolute: String), style: FallEventTypeStyle) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // 未讀紅點:6pt 圓點對齊主文字 baseline,提供明確視覺差異而不擾動既有版面。
            if isUnread {
                Circle()
                    .fill(Color(red: 0xD9 / 255, green: 0x2D / 255, blue: 0x20 / 255))
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("未讀")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.bodyLarge.weight(isUnread ? .bold : .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(time.relative)
                        .font(.captionText.weight(.medium))
                        .foregroundStyle(style.color)
                    Text("·")
                        .font(.captionText)
                        .foregroundStyle(Color.textTertiary)
                    Text(time.absolute)
                        .font(.captionText)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
    }
}

