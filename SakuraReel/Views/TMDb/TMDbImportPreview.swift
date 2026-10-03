//
//  TMDbImportPreview.swift
//  SakuraReel
//
//  Created by OpenAI Codex on behalf of zzf on 2026/10/2.
//
import SwiftUI

struct TMDbImportPreview: View {
    @Environment(MediaRepository.self) private var repository
    private var dismiss = LibraryPopupDismiss()
    let existing: MediaItem
    var onApply: (TMDbImportDraft, Set<MetadataField>) async throws -> Void
    @State private var draft: TMDbImportDraft
    @State private var fields: Set<MetadataField>
    @State private var selectedPoster: String
    @State private var loadingPoster = false
    @State private var applying = false
    @State private var duplicateDetail: PresentedMedia?
    @State private var error: String?
    @State private var posterTask: Task<Void, Never>?
    @State private var posterRequest = UUID()
    init(draft: TMDbImportDraft, existing: MediaItem,
         onApply: @escaping (TMDbImportDraft, Set<MetadataField>) async throws -> Void) {
        self.existing = existing; self.onApply = onApply
        _draft = State(initialValue: draft); _fields = State(initialValue: draft.defaults(for: existing))
        _selectedPoster = State(initialValue: draft.metadata.posterPath ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                if !draft.posterCandidates.isEmpty {
                    Section {
                        ScrollView(.horizontal) {
                            HStack(spacing: 12) {
                                ForEach(draft.posterCandidates, id: \.self) { path in
                                    Button { selectedPoster = path; fetchPoster() } label: {
                                        TMDbRemoteImage(path: path).frame(width: 88, height: 132)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay { RoundedRectangle(cornerRadius: 12).stroke(selectedPoster == path ? Constants.brandTitlePink : .clear, lineWidth: 3) }
                                    }.buttonStyle(LibraryPressStyle()).accessibilityLabel("选择海报")
                                    .accessibilityAddTraits(selectedPoster == path ? .isSelected : [])
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        Button("重试海报", systemImage: "arrow.clockwise") { fetchPoster() }.disabled(loadingPoster)
                        if loadingPoster { ProgressView("正在下载海报") }
                    } header: { Label("海报候选", systemImage: "photo.on.rectangle").foregroundStyle(Constants.brandTitlePink) }
                }
                Section("选择填入或替换的字段") {
                    ForEach(MetadataField.allCases) { field in
                        let incoming = field.value(in: draft.previewItem)
                        if !incoming.isEmpty {
                            Toggle(isOn: Binding(get: { fields.contains(field) }, set: { if $0 { fields.insert(field) } else { fields.remove(field) } })) {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: field.previewSymbol)
                                        .font(.system(size: 19, weight: .regular))
                                        .foregroundStyle(Constants.brandTitlePink)
                                        .frame(width: 26, height: 26).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(String(localized: String.LocalizationValue(field.label))).font(.subheadline.weight(.semibold))
                                        let old = field.value(in: existing)
                                        if !old.isEmpty { Text("当前：\(old)").font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                                        Text("导入：\(incoming)").font(.subheadline).foregroundStyle(.primary).lineLimit(3)
                                    }
                                }.padding(.vertical, 6)
                            }
                        }
                    }
                }
                if let found = repository.duplicate(for: draft.source, excluding: existing.id) {
                    Section {
                        Text("收藏库已有此作品")
                        Button("打开已有条目") { duplicateDetail = PresentedMedia(id: found.id) }
                    }
                }
                if !draft.warnings.isEmpty {
                    Section("获取结果") {
                        ForEach(draft.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.circle")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .scrollContentBackground(.hidden)
            .background(Constants.libraryBackground)
            .navigationTitle("导入预览").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("应用所选字段") {
                    guard !applying else { return }
                    applying = true
                    Task {
                        defer { applying = false }
                        do { try await onApply(draft, fields); dismiss() } catch { self.error = error.localizedDescription }
                    }
                }.disabled(loadingPoster) }
            }
            .librarySheet(item: $duplicateDetail) { MediaDetailView(itemID: $0.id).environment(repository) }
            .disabled(applying)
            .onDisappear { posterTask?.cancel(); posterRequest = UUID(); loadingPoster = false }
            .tint(Constants.brandTitlePink)
        }
    }
    private func fetchPoster() {
        posterTask?.cancel(); posterRequest = UUID(); let id = posterRequest
        let path = selectedPoster
        loadingPoster = true; error = nil
        posterTask = Task {
            let environment = TMDbEnvironment.shared
            let loader = TMDbImportLoader(service: environment.service, images: environment.images)
            let bytes = await loader.image(path, role: "poster", pixels: 900)
            guard !Task.isCancelled, id == posterRequest else { return }
            loadingPoster = false
            if let bytes {
                draft.poster = bytes; draft.metadata.posterPath = path
                draft.warnings.removeAll { $0.contains("海报") }
                if existing.poster == nil { fields.insert(.poster) }
            } else { selectedPoster = draft.metadata.posterPath ?? ""; error = String(localized: "海报下载失败，可继续导入文本或手动选图。") }
        }
    }
}

struct PresentedImport: Identifiable {
    let id = UUID()
    var draft: TMDbImportDraft
}
struct PresentedMedia: Identifiable { var id: UUID }

private extension MetadataField {
    var previewSymbol: String {
        switch self {
        case .title: "textformat"
        case .originalTitle: "character.book.closed"
        case .seasonTitle: "rectangle.stack"
        case .overview: "text.alignleft"
        case .releaseDate: "calendar"
        case .genres: "tag"
        case .remoteStatus: "circle.dashed"
        case .runtimeMinutes: "clock"
        case .episodeCount: "number"
        case .tmdbRating: "star"
        case .homepage: "globe"
        case .companies: "building.2"
        case .cast: "person.2"
        case .crew: "person.crop.rectangle"
        case .seasons: "square.stack"
        case .episodes: "list.bullet.rectangle"
        case .poster: "photo"
        case .backdrop: "photo.on.rectangle"
        case .logo: "seal"
        }
    }
}
