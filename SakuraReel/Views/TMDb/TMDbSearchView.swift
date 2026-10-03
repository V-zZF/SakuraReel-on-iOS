//
//  TMDbSearchView.swift
//  SakuraReel
//
//  Created by OpenAI Codex on behalf of zzf on 2026/10/2.
//
import SwiftUI

struct TMDbSearchView: View {
    private var dismiss = LibraryPopupDismiss()
    @Environment(MediaRepository.self) private var repository
    let existing: MediaItem
    var onManualAdd: (() -> Void)? = nil
    var onImportFinished: (() -> Void)? = nil
    let onApply: (TMDbImportDraft, Set<MetadataField>) -> Void
    @State private var model = TMDbSearchModel(service: TMDbEnvironment.shared.service)
    @State private var query = ""
    @State private var category = TMDbBrowseCategory.anime
    @State private var seasonSelection: SearchSelection?
    @State private var pendingSeasonSource: MediaSource?
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
    private var searchID: String { "\(query)|\(category.rawValue)|\(language)|\(TMDbEnvironment.shared.settings.generation)" }
    private var browsing: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Picker("作品类型", selection: $category) {
                        ForEach(TMDbBrowseCategory.allCases, id: \.self) { category in
                            Text(String(localized: String.LocalizationValue(category.label))).tag(category)
                        }
                    }.pickerStyle(.segmented)
                    Menu {
                        Picker("语言", selection: $language) {
                            ForEach(TMDbSettings.languages, id: \.0) { Text($0.1).tag($0.0) }
                        }
                    } label: { Image(systemName: "globe").font(.title3).frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("资料语言")
                }.padding(.horizontal).padding(.top, 8)
                if selecting { ProgressView("正在获取作品资料").padding() }
                if let error { Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal) }
                ScrollView {
                    results(category.mediaType == .movie ? model.movies : model.series)
                        .padding(.vertical, 8)
                }
                .id(category)
                .contentMargins(.bottom, 80, for: .scrollContent)
                .ignoresSafeArea(.container, edges: .bottom)

            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索片名")
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .bottom) {
                LibraryAddCapsule(title: "手动添加") {
                    cancelSelection(); model.invalidate()
                    if let onManualAdd { onManualAdd() } else { dismiss() }
                }
                .padding(.bottom, 16)
            }
            .background(Constants.libraryBackground)
            .navigationTitle("搜索作品").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { cancelSelection(); dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("设置", systemImage: "gearshape") { settings = true } }
            }
            .task(id: searchID) {
                cancelSelection(); error = nil
                await model.search(query: query, language: language, category: category)
            }
            .onDisappear { cancelSelection(); model.invalidate() }
            .librarySheet(isPresented: $settings) { TMDbSettingsView() }
            .librarySheet(item: $selected, onDismiss: {
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
                }.environment(repository)
            }
            .librarySheet(item: $seasonSelection, onDismiss: {
                if let source = pendingSeasonSource {
                    pendingSeasonSource = nil
                    select(source)
                }
            }) { selection in
                SeasonSelectionSheet(result: selection.result, disabled: selecting) { source in
                    pendingSeasonSource = source
                }
            }
            .librarySheet(item: $detail) { MediaDetailView(itemID: $0.id).environment(repository) }
            .alert("收藏库已有此作品", isPresented: Binding(get: { duplicate != nil }, set: { if !$0 { duplicate = nil } })) {
                Button("打开已有条目") { detail = duplicate; duplicate = nil }
                Button("取消", role: .cancel) { duplicate = nil }
            }
            .tint(Constants.brandTitlePink)
        }
    }
    private func results(_ group: TMDbSearchModel.Group) -> some View {
        VStack(spacing: 20) {
            LazyVStack(spacing: 16) {
                ForEach(group.results) { result in
                    TMDbSearchCard(result: result, disabled: selecting,
                        onSelect: { select(result.source) },
                        onSeason: { seasonSelection = SearchSelection(result: result) })
                }
            }.padding(.horizontal, 16)
            if group.loading { ProgressView("加载中").padding() }
            if let error = group.error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button("重试") { loadPage(category.mediaType) }.buttonStyle(.bordered)
            } else if !group.loading && group.page > 0 && group.results.isEmpty {
                ContentUnavailableView(browsing ? "暂无热门作品" : "无搜索结果", systemImage: "film")
            }
            if group.page > 0 && group.page < group.totalPages && !group.loading && group.error == nil {
                Button("加载更多") { loadPage(category.mediaType) }.buttonStyle(.bordered)
            }
        }
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

/// Search results use a horizontal poster-and-summary row; each action has its own hit area.
private struct TMDbSearchCard: View {
    let result: TMDbSearchResult
    let disabled: Bool
    let onSelect: () -> Void
    let onSeason: () -> Void
    @ScaledMetric(relativeTo: .body) private var posterWidth: CGFloat = 75

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Button(action: onSelect) {
                TMDbRemoteImage(path: result.posterPath)
                    .frame(width: posterWidth, height: posterWidth / Constants.posterAspectRatio)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(LibraryPressStyle())
                .accessibilityLabel("选择作品：\(result.title)")
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 12) {
                    Button(action: onSelect) {
                        Text(result.title).font(.headline).foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }.buttonStyle(LibraryPressStyle())
                        .accessibilityLabel("选择作品：\(result.title)")
                    if result.source.mediaType == .series {
                        Button("单季", action: onSeason)
                            .buttonStyle(.bordered).buttonBorderShape(.capsule)
                            .controlSize(.small).fixedSize()
                            .accessibilityLabel("单季：\(result.title)")
                    } else {
                        Button("选择", action: onSelect)
                            .buttonStyle(.bordered).buttonBorderShape(.capsule)
                            .controlSize(.small).fixedSize()
                    }
                }
                Button(action: onSelect) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let date = result.date, !date.isEmpty {
                            Text(date).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let overview = result.overview, !overview.isEmpty {
                            Text(overview).font(.subheadline).foregroundStyle(.secondary)
                                .lineLimit(3).multilineTextAlignment(.leading)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }.buttonStyle(LibraryPressStyle())
                    .accessibilityLabel("选择作品：\(result.title)")
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .disabled(disabled)
    }
}

private struct TMDbResultRow: View {
    let result: TMDbSearchResult
    let disabled: Bool
    let onSelect: (MediaSource) -> Void
    @State private var bySeason = true
    @State private var seasons: [MediaPart] = []
    @State private var loading = false
    @State private var error: String?
    @State private var retry = 0
    private var identity: String { "\(result.id):\(result.source.language):\(bySeason):\(retry)" }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                TMDbRemoteImage(path: result.posterPath).frame(width: 75, height: 112).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text(result.title).font(.headline).foregroundStyle(.primary)
                    if let date = result.date, !date.isEmpty { Text(date).font(.caption).foregroundStyle(.secondary) }
                    if let overview = result.overview, !overview.isEmpty { Text(overview).font(.caption).lineLimit(3).foregroundStyle(.secondary) }
                    if !bySeason { Button("选择") { onSelect(result.source) }.buttonStyle(.bordered).controlSize(.small).disabled(disabled) }
                }
            }
            if result.source.mediaType == .series {
                Picker("剧集录入方式", selection: $bySeason) { Text("整部剧集").tag(false); Text("按季").tag(true) }.pickerStyle(.segmented).disabled(disabled)
                if bySeason {
                    if loading { ProgressView("加载季度") }
                    if let error { Text(error).font(.caption).foregroundStyle(.secondary); Button("重试季度") { retry += 1 }.buttonStyle(.borderless).disabled(disabled) }
                    if !loading && error == nil && seasons.isEmpty { Text("暂无季度资料").foregroundStyle(.secondary) }
                    ForEach(seasons) { season in
                        Button {
                            let source = MediaSource(tmdb: .season(id: season.id, seriesID: result.source.remoteID, number: season.number), language: result.source.language, fetchedAt: Date())
                            onSelect(source)
                        } label: {
                            HStack(spacing: 12) {
                                Text(season.title).foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                Text("选择").font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Constants.brandTitlePink).fixedSize()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                        }
                        // List's automatic style treats multiple buttons as one row action.
                        .buttonStyle(LibraryPressStyle())
                        .disabled(disabled)
                        .accessibilityLabel("选择季度：\(season.title)")
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

private struct SearchSelection: Identifiable {
    let result: TMDbSearchResult
    var id: String { result.id }
}


private struct SeasonSelectionSheet: View {
    private var dismiss = LibraryPopupDismiss()
    let result: TMDbSearchResult
    let disabled: Bool
    let onSelect: (MediaSource) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                TMDbResultRow(result: result, disabled: disabled) { source in
                    onSelect(source)
                    dismiss()
                }.padding()
            }
            .navigationTitle("按季选择").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .tint(Constants.brandTitlePink)
        }
    }
}
