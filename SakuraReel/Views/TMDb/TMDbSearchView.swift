//
//  TMDbSearchView.swift
//  SakuraReel
//
//  Created by OpenAI Codex on behalf of zzf on 2026/10/2.
//
import SwiftUI

struct TMDbSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MediaRepository.self) private var repository
    let existing: MediaItem
    var onManualAdd: (() -> Void)? = nil
    var onImportFinished: (() -> Void)? = nil
    let onApply: (TMDbImportDraft, Set<MetadataField>) -> Void
    @State private var model = TMDbSearchModel(service: TMDbEnvironment.shared.service)
    @State private var query = ""
    @State private var type = "all"
    @State private var language = TMDbEnvironment.shared.settings.language
    @State private var settings = false
    @State private var didApply = false
    @State private var pageTasks: [TMDbMediaType: Task<Void, Never>] = [:]
    @State private var selected: PresentedImport?
    @State private var detail: PresentedMedia?
    @State private var duplicate: PresentedMedia?
    @State private var selectionTask: Task<Void, Never>?
    @State private var selectionID = UUID()
    @State private var selecting = false
    @State private var error: String?
    private var searchID: String { "\(query)|\(type)|\(language)|\(TMDbEnvironment.shared.settings.generation)" }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").accessibilityHidden(true)
                    TextField("搜索片名", text: $query).submitLabel(.search).autocorrectionDisabled()
                    if !query.isEmpty { Button("清空") { query = "" } }
                }.padding(.horizontal).padding(.top).padding(.bottom, 8)
                HStack {
                    Picker("语言", selection: $language) { ForEach(TMDbSettings.languages, id: \.0) { Text($0.1).tag($0.0) } }
                    Picker("作品类型", selection: $type) { Text("全部").tag("all"); Text("剧集").tag("series"); Text("电影").tag("movie") }
                }.padding(.horizontal)
                if selecting { ProgressView("正在获取作品资料").padding() }
                if let error { Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal) }
                List {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView("从 TMDb 搜索作品", systemImage: "magnifyingglass", description: Text("搜索电影或剧集，将资料填入现有表单。"))
                    } else {
                        if type != "movie" { results(model.series, type: .series, title: "剧集") }
                        if type != "series" { results(model.movies, type: .movie, title: "电影") }
                    }
                }.listStyle(.insetGrouped)
            }
            .safeAreaInset(edge: .bottom) {
                Button("手动添加", systemImage: "square.and.pencil") {
                    cancelSelection(); model.invalidate()
                    if let onManualAdd { onManualAdd() } else { dismiss() }
                }
                .buttonStyle(.bordered).frame(maxWidth: .infinity).padding()
                .background(.bar)
            }
            .navigationTitle("搜索作品").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { cancelSelection(); dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("设置", systemImage: "gearshape") { settings = true } }
            }
            .task(id: searchID) {
                cancelSelection(); error = nil
                await model.search(query: query, language: language, type: type)
            }
            .onDisappear { cancelSelection(); model.invalidate() }
            .sheet(isPresented: $settings) { TMDbSettingsView() }
            .sheet(item: $selected, onDismiss: {
                if didApply {
                    didApply = false
                    if let onImportFinished { onImportFinished() } else { dismiss() }
                }
            }) { selection in
                TMDbImportPreview(draft: selection.draft, existing: existing) { draft, fields in
                    if let found = repository.duplicate(for: draft.source, excluding: existing.id) {
                        duplicate = PresentedMedia(id: found.id); throw RepositoryError.duplicate
                    }
                    onApply(draft, fields)
                    didApply = true
                }
            }
            .sheet(item: $detail) { MediaDetailView(itemID: $0.id) }
            .alert("收藏库已有此作品", isPresented: Binding(get: { duplicate != nil }, set: { if !$0 { duplicate = nil } })) {
                Button("打开已有条目") { detail = duplicate; duplicate = nil }
                Button("取消", role: .cancel) { duplicate = nil }
            }
            .tint(Constants.accentPink)
        }
    }
    private func results(_ group: TMDbSearchModel.Group, type: TMDbMediaType, title: String) -> some View {
        Section {
            ForEach(group.results) { result in
                TMDbResultRow(result: result, disabled: selecting, onSelect: select)
            }
            if group.loading { ProgressView("加载中") }
            if let error = group.error {
                Text(error).font(.caption).foregroundStyle(.secondary)
                Button("重试") { loadPage(type) }
            } else if !group.loading && group.page > 0 && group.results.isEmpty { Text("无搜索结果").foregroundStyle(.secondary) }
            if group.page > 0 && group.page < group.totalPages && !group.loading && group.error == nil {
                Button("加载更多") { loadPage(type) }
            }
        } header: { Text(String(localized: String.LocalizationValue(title))) }
    }
    private func loadPage(_ type: TMDbMediaType) {
        pageTasks[type]?.cancel()
        pageTasks[type] = Task { await model.load(type) }
    }
    private func cancelSelection() {
        for task in pageTasks.values { task.cancel() }; pageTasks.removeAll()
        selectionID = UUID(); selectionTask?.cancel(); selecting = false }
    private func select(_ source: MediaSource) {
        if let found = repository.duplicate(for: source, excluding: existing.id) { duplicate = PresentedMedia(id: found.id); return }
        cancelSelection(); let id = selectionID; selecting = true; error = nil
        selectionTask = Task {
            do {
                let environment = TMDbEnvironment.shared
                let draft = try await TMDbImportLoader(service: environment.service, images: environment.images).load(source)
                guard !Task.isCancelled, id == selectionID else { return }
                selected = PresentedImport(draft: draft)
            } catch {
                guard !Task.isCancelled, id == selectionID else { return }
                self.error = error.localizedDescription
            }
            selecting = false
        }
    }
}

private struct TMDbResultRow: View {
    let result: TMDbSearchResult
    let disabled: Bool
    let onSelect: (MediaSource) -> Void
    @State private var bySeason = false
    @State private var seasons: [MediaPart] = []
    @State private var loading = false
    @State private var error: String?
    @State private var retry = 0
    private var identity: String { "\(result.id):\(result.source.language):\(bySeason):\(retry)" }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                TMDbRemoteImage(path: result.posterPath).frame(width: 75, height: 112).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 5) {
                    Text(result.title).font(.headline)
                    if let date = result.date, !date.isEmpty { Text(date).font(.caption).foregroundStyle(.secondary) }
                    if let overview = result.overview, !overview.isEmpty { Text(overview).font(.caption).lineLimit(3).foregroundStyle(.secondary) }
                    if !bySeason { Button("选择") { onSelect(result.source) }.buttonStyle(.bordered).disabled(disabled) }
                }
            }
            if result.source.mediaType == .series {
                Picker("剧集录入方式", selection: $bySeason) { Text("整部剧集").tag(false); Text("按季").tag(true) }.pickerStyle(.segmented)
                if bySeason {
                    if loading { ProgressView("加载季度") }
                    if let error { Text(error).font(.caption); Button("重试季度") { retry += 1 } }
                    if !loading && error == nil && seasons.isEmpty { Text("暂无季度资料").foregroundStyle(.secondary) }
                    ForEach(seasons) { season in
                        Button {
                            let source = MediaSource(mediaType: .season, remoteID: season.id, parentSeriesID: result.source.remoteID,
                                seasonNumber: season.number, language: result.source.language, fetchedAt: Date())
                            onSelect(source)
                        } label: {
                            HStack { Text(season.title); Spacer(); Text("选择").font(.caption) }
                        }.disabled(disabled)
                    }
                }
            }
        }
        .task(id: identity) {
            guard bySeason else { return }
            let id = identity; loading = true; error = nil
            do {
                let draft = try await TMDbEnvironment.shared.service.details(result.source)
                guard !Task.isCancelled, id == identity else { return }
                seasons = draft.metadata.seasons; loading = false
            } catch {
                guard !Task.isCancelled, id == identity else { return }
                self.error = error.localizedDescription; loading = false
            }
        }
    }
}
