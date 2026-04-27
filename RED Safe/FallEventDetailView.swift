import SwiftUI

// MARK: - Snapshot Kind Mapping

/// 後端 `kind` 欄位的中文標籤；對照 Core/edge 實際送出的 lowercase snake_case
/// (pre_fall_2s / pre_fall_500ms / fall_moment / post_fall_2s / recovery /
/// live_escalation_*)，並向後相容舊式大寫鍵。
enum FallSnapshotKind {
    case before2s
    case before05s
    case impact
    case after2s
    case recovered
    case liveEscalation
    case unknown(String)

    init(rawValue raw: String) {
        let key = raw.lowercased()
        switch key {
        case "pre_fall_2s", "before_2s":
            self = .before2s
        case "pre_fall_500ms", "pre_fall_0_5s", "before_500ms", "before_0_5s":
            self = .before05s
        case "fall_moment", "impact":
            self = .impact
        case "post_fall_2s", "after_2s":
            self = .after2s
        case "recovery", "recovered":
            self = .recovered
        default:
            if key.hasPrefix("live_escalation") {
                self = .liveEscalation
            } else {
                self = .unknown(raw)
            }
        }
    }

    var displayName: String {
        switch self {
        case .before2s:        return "跌倒前 2 秒"
        case .before05s:       return "跌倒前 0.5 秒"
        case .impact:          return "跌倒瞬間"
        case .after2s:         return "跌倒後 2 秒"
        case .recovered:       return "爬起時"
        case .liveEscalation:  return "持續未起身"
        case .unknown(let raw): return raw.isEmpty ? "未知時點" : raw
        }
    }
}

// MARK: - View

/// 跌倒事件詳情頁。
/// 視覺上沿用 GlassContainer / AppFont / Color tokens，三事件配色嚴格對齊 backend EmailService。
struct FallEventDetailView: View {
    let edgeId: String
    let eventId: String

    @State private var detail: FallEventDetail?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var selectedIndex = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                if let detail {
                    eventTypeBanner(detail: detail)
                    imageTimeline(detail: detail)
                    metadataCard(detail: detail)
                } else if let loadError {
                    errorState(message: loadError)
                } else {
                    loadingState
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Color.appBackground)
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("事件詳情")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onAppear {
            // 進入詳情頁即視為已讀;不等載入完成,避免讀取失敗時無法標記。
            FallEventReadStore.markRead(eventId)
        }
    }

    // MARK: - Banner

    private func eventTypeBanner(detail: FallEventDetail) -> some View {
        let style = FallEventTypeStyle(rawValue: detail.eventType)
        let time = FallEventDateFormat.displayPair(for: detail.eventTime)

        return HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 56, height: 56)
                Image(systemName: style.icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.white)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(style.label)
                    .font(.displaySmall)
                    .foregroundStyle(Color.white)
                Text("\(time.relative)・\(time.absolute)")
                    .font(.captionText)
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(style.color)
        )
        .shadow(color: style.color.opacity(0.25), radius: 18, x: 0, y: 10)
    }

    // MARK: - Image timeline

    private func imageTimeline(detail: FallEventDetail) -> some View {
        let snapshots = detail.snapshots
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle("快照時間軸")

            if snapshots.isEmpty {
                GlassContainer(padding: 20) {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title3)
                            .foregroundStyle(Color.textTertiary)
                        Text("此事件無快照")
                            .font(.bodyMedium)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                    }
                }
            } else {
                pager(snapshots: snapshots)
                if !snapshots.isEmpty {
                    captionForCurrent(snapshots: snapshots)
                    thumbnailStrip(snapshots: snapshots)
                }
            }
        }
    }

    private func pager(snapshots: [FallSnapshotMeta]) -> some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, snapshot in
                AuthenticatedAsyncImage(
                    url: APIClient.shared.fallSnapshotURL(path: snapshot.url, edgeId: edgeId),
                    cacheKey: snapshot.snapshotId,
                    contentMode: .fit,
                    accessibilityLabel: "\(FallSnapshotKind(rawValue: snapshot.kind).displayName)快照"
                )
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.border, lineWidth: 1)
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .frame(height: 320)
    }

    private func captionForCurrent(snapshots: [FallSnapshotMeta]) -> some View {
        let safeIndex = min(max(selectedIndex, 0), snapshots.count - 1)
        let snapshot = snapshots[safeIndex]
        let kind = FallSnapshotKind(rawValue: snapshot.kind)
        let offsetText: String? = snapshot.offsetMs.map { ms in
            let seconds = Double(ms) / 1000
            return String(format: "偏移 %+.1f 秒", seconds)
        }
        return HStack(spacing: 8) {
            Image(systemName: "camera.aperture")
                .font(.captionText)
                .foregroundStyle(Color.textSecondary)
            Text(kind.displayName)
                .font(.bodyMedium.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            if let offsetText {
                Text("·")
                    .foregroundStyle(Color.textTertiary)
                Text(offsetText)
                    .font(.captionText)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Text("\(safeIndex + 1) / \(snapshots.count)")
                .font(.captionText.monospaced())
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 4)
    }

    private func thumbnailStrip(snapshots: [FallSnapshotMeta]) -> some View {
        // ScrollViewReader 讓 TabView swipe 也能反向同步 thumbnail strip 的可見焦點。
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, snapshot in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedIndex = index
                            }
                        } label: {
                            AuthenticatedAsyncImage(
                                url: APIClient.shared.fallSnapshotURL(path: snapshot.url, edgeId: edgeId),
                                cacheKey: snapshot.snapshotId,
                                contentMode: .fill,
                                accessibilityLabel: "\(FallSnapshotKind(rawValue: snapshot.kind).displayName)縮圖"
                            )
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(
                                        selectedIndex == index ? Color.primaryBrand : Color.border,
                                        lineWidth: selectedIndex == index ? 2 : 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding(.horizontal, 4)
            }
            .onChange(of: selectedIndex) { _, new in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
    }

    // MARK: - Metadata

    private func metadataCard(detail: FallEventDetail) -> some View {
        VStack(spacing: 16) {
            cameraInfoCard(detail: detail)
            timingCard(detail: detail)
            evidenceCard(detail: detail)
        }
    }

    private func cameraInfoCard(detail: FallEventDetail) -> some View {
        GlassContainer(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle(icon: "camera.fill", text: "攝影機")
                infoRow(label: "自訂名稱", value: detail.cameraCustomName?.nonEmpty ?? "—")
                infoRow(label: "IP", value: detail.cameraIp?.nonEmpty ?? "—", monospaced: true)
                infoRow(label: "MAC", value: detail.cameraMac?.nonEmpty ?? "—", monospaced: true)
                infoRow(label: "型號", value: detail.cameraIpcName?.nonEmpty ?? "—")
                infoRow(label: "位置", value: detail.location?.nonEmpty ?? "—")
            }
        }
    }

    private func timingCard(detail: FallEventDetail) -> some View {
        let occurred = FallEventDateFormat.displayPair(for: detail.eventTime)
        let recovered = detail.recoveredAt.map { FallEventDateFormat.displayPair(for: $0) }
        return GlassContainer(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle(icon: "clock.fill", text: "時間軸")
                infoRow(label: "發生時間", value: occurred.absolute)
                infoRow(label: "相對時間", value: occurred.relative)
                infoRow(label: "恢復時間", value: recovered?.absolute ?? "—")
                if let lying = detail.lyingSustainSeconds {
                    infoRow(label: "倒地持續", value: String(format: "%.1f 秒", lying))
                }
            }
        }
    }

    private func evidenceCard(detail: FallEventDetail) -> some View {
        GlassContainer(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle(icon: "waveform.path.ecg", text: "AI 偵測證據")
                if let lying = detail.lyingSustainSeconds {
                    infoRow(label: "倒地秒數", value: String(format: "%.1f s", lying))
                }
                if let energy = detail.fallEnergy {
                    infoRow(label: "下降能量", value: String(format: "%.2f", energy))
                }
                if let person = detail.personId {
                    infoRow(label: "人員 ID", value: "#\(person)")
                }
                vlmRow(detail: detail)
            }
        }
    }

    private func vlmRow(detail: FallEventDetail) -> some View {
        let confirmed = detail.vlmConfirmed ?? false
        let confidencePct: String? = detail.vlmConfidence.map { String(format: "%.0f%%", $0 * 100) }
        let label: String
        let color: Color
        let icon: String
        if confirmed {
            label = confidencePct.map { "AI 已確認（\($0)）" } ?? "AI 已確認"
            color = Color(red: 0x0E / 255, green: 0x93 / 255, blue: 0x84 / 255)
            icon = "checkmark.seal.fill"
        } else {
            label = "未經 AI 二次確認"
            color = Color(red: 0x47 / 255, green: 0x54 / 255, blue: 0x67 / 255)
            icon = "questionmark.circle"
        }
        return HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(label)
                .font(.bodyMedium.weight(.medium))
                .foregroundStyle(color)
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Sub-elements

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.bodyLarge.weight(.semibold))
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 4)
    }

    private func cardTitle(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.bodyMedium)
                .foregroundStyle(Color.primaryBrand)
            Text(text)
                .font(.bodyLarge.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
        }
    }

    private func infoRow(label: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(monospaced ? .bodyMedium.monospaced() : .bodyMedium)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView().tint(Color.primaryBrand)
            Text("載入事件詳情中…")
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func errorState(message: String) -> some View {
        GlassContainer(padding: 24) {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(Color.errorRed)
                Text("無法載入事件詳情")
                    .font(.bodyLarge.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(message)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await load() }
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

    // MARK: - Loading

    private func load() async {
        // 並發守衛:.task 在二次出現時可能再次觸發,且重試 button 會手動呼叫,避免雙重請求。
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let result = try await APIClient.shared.fetchFallEventDetail(edgeId: edgeId, eventId: eventId)
            detail = result
            selectedIndex = 0
        } catch {
            loadError = error.localizedDescription
        }
    }
}
