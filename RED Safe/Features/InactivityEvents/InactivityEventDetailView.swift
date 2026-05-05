import SwiftUI

// MARK: - Snapshot Kind Mapping

/// 靜止事件 snapshot 的 `kind` 標籤;對齊 backend `inactivity_event_snapshots.kind`
/// 三值 `pre` / `trigger` / `post`(分別為 -2s / 0s / +2s)。
enum InactivitySnapshotKind {
    case pre
    case trigger
    case post
    case unknown(String)

    init(rawValue raw: String) {
        switch raw.lowercased() {
        case "pre", "pre_2s", "before_2s":
            self = .pre
        case "trigger", "moment":
            self = .trigger
        case "post", "post_2s", "after_2s":
            self = .post
        default:
            self = .unknown(raw)
        }
    }

    var displayName: String {
        switch self {
        case .pre:               return "觸發前 2 秒"
        case .trigger:           return "觸發瞬間"
        case .post:              return "觸發後 2 秒"
        case .unknown(let raw):  return raw.isEmpty ? "未知時點" : raw
        }
    }
}

// MARK: - View

/// 長時間靜止事件詳情頁。沿用 fall 詳情的視覺結構,僅:
/// - 改用單一 accent 配色(`InactivityEventStyle.accent`)
/// - 移除 fall 特有的 `lyingSustainSeconds` / `fallEnergy` / `recoveredAt`,
///   改顯示 `idleSeconds`
struct InactivityEventDetailView: View {
    let edgeId: String
    let eventId: String

    @State private var detail: InactivityEventDetail?
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
            InactivityEventReadStore.markRead(eventId)
        }
    }

    // MARK: - Banner

    private func eventTypeBanner(detail: InactivityEventDetail) -> some View {
        let time = InactivityEventDateFormat.displayPair(for: detail.eventTime)

        return HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 56, height: 56)
                Image(systemName: InactivityEventStyle.icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.white)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(InactivityEventStyle.label)
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
                .fill(InactivityEventStyle.accent)
        )
        .shadow(color: InactivityEventStyle.accent.opacity(0.25), radius: 18, x: 0, y: 10)
    }

    // MARK: - Image timeline

    private func imageTimeline(detail: InactivityEventDetail) -> some View {
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
                captionForCurrent(snapshots: snapshots)
                thumbnailStrip(snapshots: snapshots)
            }
        }
    }

    private func pager(snapshots: [FallSnapshotMeta]) -> some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, snapshot in
                AuthenticatedAsyncImage(
                    url: APIClient.shared.inactivitySnapshotURL(path: snapshot.url, edgeId: edgeId),
                    cacheKey: "inactivity-\(snapshot.snapshotId)",
                    contentMode: .fit,
                    accessibilityLabel: "\(InactivitySnapshotKind(rawValue: snapshot.kind).displayName)快照"
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
        let kind = InactivitySnapshotKind(rawValue: snapshot.kind)
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
                                url: APIClient.shared.inactivitySnapshotURL(path: snapshot.url, edgeId: edgeId),
                                cacheKey: "inactivity-\(snapshot.snapshotId)",
                                contentMode: .fill,
                                accessibilityLabel: "\(InactivitySnapshotKind(rawValue: snapshot.kind).displayName)縮圖"
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

    private func metadataCard(detail: InactivityEventDetail) -> some View {
        VStack(spacing: 16) {
            cameraInfoCard(detail: detail)
            timingCard(detail: detail)
            evidenceCard(detail: detail)
        }
    }

    private func cameraInfoCard(detail: InactivityEventDetail) -> some View {
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

    private func timingCard(detail: InactivityEventDetail) -> some View {
        let occurred = InactivityEventDateFormat.displayPair(for: detail.eventTime)
        return GlassContainer(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle(icon: "clock.fill", text: "時間軸")
                infoRow(label: "觸發時間", value: occurred.absolute)
                infoRow(label: "相對時間", value: occurred.relative)
                infoRow(label: "靜止時長", value: formatIdle(detail.idleSeconds))
            }
        }
    }

    private func evidenceCard(detail: InactivityEventDetail) -> some View {
        GlassContainer(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle(icon: "waveform.path.ecg", text: "AI 偵測證據")
                infoRow(label: "靜止秒數", value: String(format: "%.1f s", detail.idleSeconds))
                if let person = detail.personId {
                    infoRow(label: "人員 ID", value: "#\(person)")
                }
            }
        }
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

    private func formatIdle(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total >= 60 {
            let m = total / 60
            let s = total % 60
            return s == 0 ? "\(m) 分鐘" : "\(m) 分 \(s) 秒"
        }
        return "\(total) 秒"
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
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let result = try await APIClient.shared.fetchInactivityEventDetail(edgeId: edgeId, eventId: eventId)
            detail = result
            selectedIndex = 0
        } catch {
            loadError = error.localizedDescription
        }
    }
}
