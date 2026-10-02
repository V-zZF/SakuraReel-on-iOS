import SwiftUI

/// 添加 / 编辑表单 Sheet。
///
/// `initialItem` 为 nil 时是添加模式，非 nil 时是编辑模式。
/// 通过 `onSave` / `onDelete` 与上层（HomeView）交互，由上层调用 `MediaRepository` 完成持久化。
struct AddEditMediaView: View {
    @Environment(MediaRepository.self) private var repository
    @Environment(\.dismiss) private var dismiss

    let initialItem: MediaItem?
    var initialDraft: MediaItem? = nil
    var onSave: (MediaItem) async throws -> Void
    var onDelete: (() async throws -> Void)?

    // 表单状态
    @State private var isSaving = false
    @State private var title: String = ""
    @State private var status: MediaStatus = .watched
    @State private var watchYear: Int? = nil
    @State private var watchMonth: Int? = nil
    @State private var rating: Int = 0
    @State private var review: String = ""
    @State private var playURL: String = ""
    @State private var posterData: Data? = nil

    @State private var source: MediaSource?
    @State private var metadata: MediaMetadata?
    @State private var backdrop: Data?
    @State private var logo: Data?
    @State private var initialized = false
    @State private var localID = UUID()
    @State private var showsTMDbSearch = false
    @State private var showsMetadataEditor = false
    @State private var existingDetail: PresentedMedia?
    @State private var saveError: String?

    // 弹窗状态
    @State private var showDeleteAlert = false
    @State private var showUnsavedAlert = false
    @State private var showEmptyTitleAlert = false

    private var isEditMode: Bool { initialItem != nil }

    /// 是否有未保存修改。
    ///
    /// 海报直接比较压缩后的 `Data?`（两侧字节可比），避免重编码 JPEG 字节漂移
    /// 导致「编辑但未改海报」也被判定为有修改。
    private var isDirty: Bool {
        if isEditMode {
            let base = initialItem
            return source != base?.source || metadata != base?.metadata
                || backdrop != base?.backdrop || logo != base?.logo
                || title != (base?.title ?? "")
                || status != (base?.status ?? .watched)
                || watchYear != base?.watchYear
                || watchMonth != base?.watchMonth
                || rating != (base?.rating ?? 0)
                || review != (base?.review ?? "")
                || playURL != (base?.playURL ?? "")
                || posterData != (base?.poster ?? nil)
        } else {
            return source != nil || metadata != nil || backdrop != nil || logo != nil || !title.isEmpty || !review.isEmpty || !playURL.isEmpty
                || posterData != nil
                || status != .watched
                || rating != 0
                || watchYear != nil || watchMonth != nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - 海报
                Section(header: Text("影片海报")) {
                    PosterImagePicker(posterData: $posterData)
                }

                // MARK: - 基本信息
                Section(header: Text("基本信息")) {
                    HStack(spacing: 10) {
                        fieldIcon("film")
                        TextField("片名 (必填)", text: $title)
                    }

                    Picker(selection: $status) {
                        ForEach(MediaStatus.allCases, id: \.id) { s in
                            Text(s.displayName).tag(s)
                        }
                    } label: {
                        Label("分类", systemImage: "square.grid.2x2")
                    }

                    YearMonthPickers(year: $watchYear, month: $watchMonth)
                }

                // MARK: - 评价与链接
                Section(header: Text("评价与链接")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("评分", systemImage: "star")
                            Spacer()
                            if rating > 0 {
                                Text("\(rating) 分")
                                    .bold()
                                    .foregroundStyle(RatingColor.color(for: rating))
                            } else {
                                Text("未评分")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Slider(
                            value: Binding(
                                get: { Double(rating) },
                                set: { rating = Int($0.rounded()) }
                            ),
                            in: 0...10,
                            step: 1
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Label("短评", systemImage: "text.bubble")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $review)
                            .frame(height: 80)
                    }

                    HStack(spacing: 10) {
                        fieldIcon("link")
                        TextField("播放链接 (https://)", text: $playURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                    }
                }
            }
            .navigationTitle(isEditMode ? "编辑内容" : "添加内容")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button("从 TMDb 搜索", systemImage: "magnifyingglass") { showsTMDbSearch = true }
                        Button("编辑作品资料", systemImage: "doc.text") { showsMetadataEditor = true }
                    } label: { Label("作品资料", systemImage: "doc.text.magnifyingglass") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        attemptClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomActionBar
            }
            .tint(Constants.accentPink)
            .disabled(isSaving)
            .alert("放弃修改？", isPresented: $showUnsavedAlert) {
                Button("放弃修改", role: .destructive) { dismiss() }
                Button("继续编辑", role: .cancel) {}
            } message: {
                Text("您有未保存的内容，离开后修改将丢失。")
            }
            .alert("确认删除", isPresented: $showDeleteAlert) {
                Button("删除", role: .destructive) {
                    Task { do { try await onDelete?(); dismiss() } catch { saveError = error.localizedDescription } }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后不可恢复，确定要删除吗？")
            }
            .alert("请填写片名", isPresented: $showEmptyTitleAlert) {
                Button("好的", role: .cancel) {}
            } message: {
                Text("保存前需要先填写片名。")
            }
            .onAppear(perform: populateFields)
            .modifier(UnsavedDismissGuard(isDirty: isDirty, onAttempt: { showUnsavedAlert = true }))
            .sheet(isPresented: $showsTMDbSearch) {
                TMDbSearchView(existing: currentDraft) { draft, fields in
                    adoptMetadata(draft.merging(into: currentDraft, fields: fields))
                }
            }
            .sheet(item: $existingDetail) { MediaDetailView(itemID: $0.id) }
            .sheet(isPresented: $showsMetadataEditor) {
                MediaMetadataEditor(initialItem: currentDraft) { adoptMetadata($0) }
            }
            .alert("保存失败", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("继续编辑", role: .cancel) {}
                if let source, let found = repository.duplicate(for: source, excluding: currentDraft.id) {
                    Button("打开已有条目") { existingDetail = PresentedMedia(id: found.id) }
                }
            } message: { Text(saveError ?? "") }
        }
    }

    // MARK: - iOS 原生底部按钮栏

    private func fieldIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .foregroundStyle(.secondary)
            .frame(width: 20)
            .accessibilityHidden(true)
    }

    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            // [删除按钮] - 仅编辑模式显示，系统破坏性样式
            if isEditMode {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Text("删除")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            // [取消按钮] - 系统 Bordered 原生外观
            Button {
                attemptClose()
            } label: {
                Text("取消")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.primary)

            // [保存按钮] - BorderedProminent 突出样式 + 樱花粉 Theme Tint
            Button {
                Task { await handleSave() }
            } label: {
                Text("保存")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Constants.accentPink)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.regularMaterial) // 原生毛玻璃底部衬底
    }

    // MARK: - 行为

    private func populateFields() {
        guard !initialized else { return }
        initialized = true
        guard let item = initialItem ?? initialDraft else { return }
        localID = item.id
        source = item.source; metadata = item.metadata; backdrop = item.backdrop; logo = item.logo
        title = item.title
        status = item.status
        watchYear = item.watchYear
        watchMonth = item.watchMonth
        rating = item.rating
        review = item.review ?? ""
        playURL = item.playURL ?? ""
        posterData = item.poster
        // 数据一致性兜底：有年无月时补当前月
        if watchYear != nil, watchMonth == nil {
            watchMonth = Calendar.current.component(.month, from: Date())
        }
    }

    private func attemptClose() {
        if isDirty {
            showUnsavedAlert = true
        } else {
            dismiss()
        }
    }

    private var currentDraft: MediaItem {
        let trimmedReview = review.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = playURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var item = MediaItem(id: initialItem?.id ?? localID, title: title, poster: posterData, status: status,
            watchedAt: watchYear.flatMap { year in watchMonth.map { YearMonth(year: year, month: $0) } }, rating: rating,
            review: trimmedReview.isEmpty ? nil : trimmedReview, playURL: trimmedURL.isEmpty ? nil : trimmedURL,
            createdAt: initialItem?.createdAt ?? Date(), updatedAt: initialItem?.updatedAt ?? Date(),
            source: source, metadata: metadata, backdrop: backdrop, logo: logo)
        if let base = initialItem ?? initialDraft {
            if posterData == base.poster { item.attachments.poster = base.attachments.poster }
            if backdrop == base.backdrop { item.attachments.backdrop = base.attachments.backdrop }
            if logo == base.logo { item.attachments.logo = base.attachments.logo }
        }
        return item
    }
    private func adoptMetadata(_ item: MediaItem) {
        title = item.title; posterData = item.poster
        source = item.source; metadata = item.metadata; backdrop = item.backdrop; logo = item.logo
    }

    private func handleSave() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            showEmptyTitleAlert = true
            return
        }
        guard (watchYear == nil) == (watchMonth == nil) else {
            saveError = "请完整选择观看年份和月份。"
            return
        }
        do {
            var item = currentDraft
            item.title = trimmedTitle
            try await onSave(item)
            dismiss()
        } catch { saveError = error.localizedDescription }

    }
}

#Preview("添加") {
    AddEditMediaView(
        initialItem: nil,
        onSave: { _ in },
        onDelete: nil
    ).environment(MediaRepository(seedItems: PreviewSampleData.sampleItems))
}

#Preview("编辑") {
    AddEditMediaView(
        initialItem: PreviewSampleData.sampleItems[0],
        onSave: { _ in },
        onDelete: {}
    ).environment(MediaRepository(seedItems: PreviewSampleData.sampleItems))
}
