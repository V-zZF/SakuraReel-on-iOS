//
//  TMDbImportPreview.swift
//  SakuraReel
//
//  Created by OpenAI Codex on behalf of zzf on 2026/10/2.
//
import SwiftUI

struct TMDbImportPreview: View {
    @Environment(MediaRepository.self) private var repository
    @Environment(\.dismiss) private var dismiss
    let existing: MediaItem
    var onApply: (TMDbImportDraft, Set<MetadataField>) throws -> Void
    @State private var draft: TMDbImportDraft
    @State private var fields: Set<MetadataField>
    @State private var selectedPoster: String
    @State private var loadingPoster = false
    @State private var duplicateDetail: PresentedMedia?
    @State private var error: String?
    @State private var posterTask: Task<Void, Never>?
    @State private var posterRequest = UUID()
    init(draft: TMDbImportDraft, existing: MediaItem,
         onApply: @escaping (TMDbImportDraft, Set<MetadataField>) throws -> Void) {
        self.existing = existing; self.onApply = onApply
        _draft = State(initialValue: draft); _fields = State(initialValue: draft.defaults(for: existing))
        _selectedPoster = State(initialValue: draft.metadata.posterPath ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("仅将勾选字段填入本地资料。个人记录不会被替换。")
                    ForEach(draft.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
                if !draft.posterCandidates.isEmpty {
                    Section("海报候选") {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(draft.posterCandidates, id: \.self) { path in
                                    Button { selectedPoster = path; fetchPoster() } label: {
                                        TMDbRemoteImage(path: path).frame(width: 70, height: 105)
                                            .overlay { RoundedRectangle(cornerRadius: 4).stroke(selectedPoster == path ? Constants.accentPink : .clear, lineWidth: 3) }
                                    }.accessibilityLabel("选择海报")
                                }
                            }
                        }
                        Button("重试海报") { fetchPoster() }.disabled(loadingPoster)
                        if loadingPoster { ProgressView("正在下载海报") }
                    }
                }
                Section("选择填入或替换的字段") {
                    ForEach(MetadataField.allCases) { field in
                        let incoming = field.value(in: draft.previewItem)
                        if !incoming.isEmpty {
                            Toggle(isOn: Binding(get: { fields.contains(field) }, set: { if $0 { fields.insert(field) } else { fields.remove(field) } })) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(String(localized: String.LocalizationValue(field.label))).font(.headline)
                                    let old = field.value(in: existing)
                                    if !old.isEmpty { Text("当前：\(old)").font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                                    Text("导入：\(incoming)").font(.caption).lineLimit(3)
                                }
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
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("导入预览").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("应用所选字段") {
                    do { try onApply(draft, fields); dismiss() } catch { self.error = error.localizedDescription }
                }.disabled(loadingPoster) }
            }
            .sheet(item: $duplicateDetail) { MediaDetailView(itemID: $0.id) }
            .onDisappear { posterTask?.cancel(); posterRequest = UUID(); loadingPoster = false }
            .tint(Constants.accentPink)
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
