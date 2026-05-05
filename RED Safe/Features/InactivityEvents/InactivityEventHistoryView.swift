import SwiftUI

// MARK: - Inactivity Event Visual Tokens

/// 靜止事件的單一視覺語彙;與 backend EmailService 的「警示橘」對齊,
/// 區別於 fall 三色,讓家屬一眼識別事件性質。
enum InactivityEventStyle {
    static let accent = Color(red: 0xDC / 255, green: 0x6B / 255, blue: 0x19 / 255)
    static let label = "長時間靜止"
    static let icon = "figure.stand"
}

// MARK: - Date Formatters

@MainActor
enum InactivityEventDateFormat {
    static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.unitsStyle = .short
        return f
    }()

    static func displayPair(for iso: String, now: Date = Date()) -> (relative: String, absolute: String) {
        guard let date = RedSafeDateFormatter.parseISO(iso) else { return ("—", iso) }
        let relative = relativeFormatter.localizedString(for: date, relativeTo: now)
        let absolute = RedSafeDateFormatter.absoluteFormatter.string(from: date)
        return (relative, absolute)
    }
}

// MARK: - View

/// 長時間靜止事件歷史列表頁。
/// 設計參考 FallEventHistoryView,但移除 filter chips(後端不送 RECOVERED/SELF_RECOVERED 分流)
/// 並改顯示 idleSeconds 而非 fall 特有欄位。
struct InactivityEventHistoryView: View {
    let edge: EdgeSummary

    @State private var events: [InactivityEventSummary] = []
    @State private var loadedEventIds: Set<String> = []
    @State private var currentPage: Int = 0
    @State private var totalCount: Int = 0
    @State private var hasMore: Bool = true
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var hasLoadedOnce = false
    @State private var loadError: String?
    @State private var loadMoreError: String?

    @State private var readStore = InactivityEventReadStore.shared

    private let pageSize = 50

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                headerCard
                content
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Color.appBackground)
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("長時間靜止事件")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { markAllReadToolbar }
        .task { if !hasLoadedOnce { await reload() } }
        .refreshable { await reload() }
    }

    @ToolbarContentBuilder
    private var markAllReadToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            let unreadIds = events.filter { !readStore.readIds.contains($0.eventId) }.map(\.eventId)
            Button {
                InactivityEventReadStore.markAllRead(unreadIds)
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
                        .fill(InactivityEventStyle.accent.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: InactivityEventStyle.icon)
                        .font(.title3)
                        .foregroundStyle(InactivityEventStyle.accent)
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

    private var badgeText: String {
        let shown = events.count
        if totalCount > events.count {
            return "\(shown) / \(totalCount) 筆"
        }
        return "\(shown) 筆"
    }

    // MARK: States

    @ViewBuilder
    private var content: some View {
        if (isLoading || !hasLoadedOnce) && events.isEmpty && loadError == nil {
            loadingState
        } else if let loadError, events.isEmpty {
            errorState(message: loadError)
        } else if events.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView().tint(Color.primaryBrand)
            Text("載入靜止事件中…")
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
                Text("無法載入靜止事件")
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
                Text("尚無長時間靜止事件")
                    .font(.bodyLarge.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("當 Edge 偵測到人員長時間靜止時會自動上傳並顯示在此。")
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var list: some View {
        LazyVStack(spacing: 16) {
            ForEach(events) { event in
                NavigationLink {
                    InactivityEventDetailView(edgeId: edge.edgeId, eventId: event.eventId)
                } label: {
                    InactivityEventCard(
                        event: event,
                        edgeId: edge.edgeId,
                        isUnread: !readStore.readIds.contains(event.eventId)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .onAppear {
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

    private func reload() async {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        loadMoreError = nil
        defer {
            isLoading = false
            hasLoadedOnce = true
        }
        do {
            let response = try await APIClient.shared.fetchInactivityEvents(
                edgeId: edge.edgeId,
                page: 0,
                size: pageSize
            )
            events = response.events
            loadedEventIds = Set(response.events.map(\.eventId))
            totalCount = response.total
            currentPage = 0
            hasMore = computeHasMore(loaded: events.count, total: response.total, lastBatch: response.events.count)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadMoreIfNeeded(force: Bool = false) async {
        guard hasLoadedOnce, !isLoading, !isLoadingMore, hasMore else { return }
        guard force || loadMoreError == nil else { return }

        isLoadingMore = true
        loadMoreError = nil
        defer { isLoadingMore = false }

        let nextPage = currentPage + 1
        do {
            let response = try await APIClient.shared.fetchInactivityEvents(
                edgeId: edge.edgeId,
                page: nextPage,
                size: pageSize
            )
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

    private func computeHasMore(loaded: Int, total: Int, lastBatch: Int) -> Bool {
        if total > 0 { return loaded < total }
        return lastBatch >= pageSize
    }
}

// MARK: - Card

private struct InactivityEventCard: View {
    let event: InactivityEventSummary
    let edgeId: String
    let isUnread: Bool

    var body: some View {
        let displayTime = InactivityEventDateFormat.displayPair(for: event.eventTime)
        let title = event.cameraCustomName?.nonEmpty ?? event.cameraIp ?? "未知攝影機"

        return GlassContainer(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                thumbnail
                metadata(title: title, time: displayTime)
            }
        }
    }

    private var thumbnail: some View {
        ZStack(alignment: .topTrailing) {
            thumbnailImage
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 6) {
                Image(systemName: InactivityEventStyle.icon)
                    .font(.captionText)
                Text(InactivityEventStyle.label)
                    .font(.captionText.weight(.semibold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(InactivityEventStyle.accent)
            .clipShape(Capsule())
            .padding(10)
        }
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let path = event.thumbnailUrl, !path.isEmpty {
            AuthenticatedAsyncImage(
                url: APIClient.shared.inactivitySnapshotURL(path: path, edgeId: edgeId),
                cacheKey: "inactivity-thumb-\(event.eventId)",
                contentMode: .fill,
                accessibilityLabel: "長時間靜止事件縮圖,\(event.cameraCustomName?.nonEmpty ?? event.cameraIp ?? "未知攝影機")"
            )
        } else {
            DefaultAuthenticatedImagePlaceholder()
        }
    }

    private func metadata(title: String, time: (relative: String, absolute: String)) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if isUnread {
                Circle()
                    .fill(InactivityEventStyle.accent)
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
                        .foregroundStyle(InactivityEventStyle.accent)
                    Text("·")
                        .font(.captionText)
                        .foregroundStyle(Color.textTertiary)
                    Text(time.absolute)
                        .font(.captionText)
                        .foregroundStyle(Color.textSecondary)
                }
                Text("靜止 \(formatIdle(event.idleSeconds))")
                    .font(.captionText)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
    }

    /// 將秒數格式化為「N 分 M 秒」或「N 秒」;支援 idleMinutes policy 預設,提升可讀性。
    private func formatIdle(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total >= 60 {
            let m = total / 60
            let s = total % 60
            return s == 0 ? "\(m) 分鐘" : "\(m) 分 \(s) 秒"
        }
        return "\(total) 秒"
    }
}
