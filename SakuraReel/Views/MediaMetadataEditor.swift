//
//  MediaMetadataEditor.swift
//  SakuraReel
//
//  Created by OpenAI Codex on behalf of zzf on 2026/10/2.
//
import SwiftUI
import PhotosUI

struct MediaMetadataEditor: View {
    @Environment(\.dismiss) private var dismiss
    let initialItem: MediaItem
    let onSave: (MediaItem) async throws -> Void
    @State private var isSaving = false
    @State private var item: MediaItem
    @State private var metadata: MediaMetadata
    @State private var numbers: [MetadataField: String]
    @State private var discard = false
    @State private var error: String?
    init(initialItem: MediaItem, onSave: @escaping (MediaItem) async throws -> Void) {
        self.initialItem = initialItem; self.onSave = onSave
        _item = State(initialValue: initialItem)
        _metadata = State(initialValue: initialItem.metadata ?? MediaMetadata())
        _numbers = State(initialValue: Dictionary(uniqueKeysWithValues: [.runtimeMinutes, .episodeCount, .tmdbRating].map { ($0, $0.value(in: initialItem)) }))
    }
    private var dirty: Bool {
        item != initialItem || metadata != (initialItem.metadata ?? MediaMetadata()) ||
        numbers != Dictionary(uniqueKeysWithValues: [.runtimeMinutes, .episodeCount, .tmdbRating].map { ($0, $0.value(in: initialItem)) })
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("作品资料") {
                    TextField("片名", text: $item.title)
                    TextField("原名", text: string(\.originalTitle))
                    TextField("季度名", text: string(\.seasonTitle))
                    TextField("简介", text: string(\.overview), axis: .vertical).lineLimit(3...8)
                    TextField("上映／首播日期（YYYY-MM-DD）", text: string(\.releaseDate))
                    TextField("影视类型（用、分隔）", text: Binding(get: { metadata.genres.joined(separator: "、") }, set: {
                        metadata.genres = $0.split(separator: "、").map(String.init)
                    }))
                    TextField("作品状态", text: string(\.remoteStatus))
                    ForEach([MetadataField.runtimeMinutes, .episodeCount, .tmdbRating]) { field in
                        TextField(String(localized: String.LocalizationValue(field.label)), text: Binding(get: { numbers[field] ?? "" }, set: { numbers[field] = $0 }))
                            .keyboardType(field == .tmdbRating ? .decimalPad : .numberPad)
                    }
                    TextField("官网", text: string(\.homepage)).keyboardType(.URL).textInputAutocapitalization(.never)
                    Text("这些是作品资料。TMDb 评分与个人 0–10 分评分独立。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("本地图片") {
                    PosterImagePicker(posterData: $item.poster)
                    Button("移除海报", role: .destructive) { item.poster = nil }
                    LocalArtworkPicker(label: "背景图", kind: "backdrop", data: $item.backdrop)
                    LocalArtworkPicker(label: "Logo", kind: "logo", data: $item.logo)
                }
                Section("制作公司") {
                    ForEach($metadata.companies) { $company in
                        HStack {
                            TextField("公司名称", text: $company.name)
                            Button("删除", role: .destructive) { metadata.companies.removeAll { $0.id == company.id } }
                        }
                    }
                    Button("添加制作公司") { metadata.companies.append(MediaCompany(id: nextID(metadata.companies.map(\.id)), name: "")) }
                }
                credits("演员", entries: $metadata.cast)
                credits("职员", entries: $metadata.crew)
                parts("季度", entries: $metadata.seasons)
                parts("单集", entries: $metadata.episodes)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("编辑作品资料").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { if dirty { discard = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } } }
            }
            .disabled(isSaving)
            .modifier(UnsavedDismissGuard(isDirty: dirty, onAttempt: { discard = true }))
            .alert("放弃修改？", isPresented: $discard) {
                Button("放弃修改", role: .destructive) { dismiss() }; Button("继续编辑", role: .cancel) {}
            }
            .tint(Constants.accentPink)
        }
    }
    private func string(_ path: WritableKeyPath<MediaMetadata, String?>) -> Binding<String> {
        Binding(get: { metadata[keyPath: path] ?? "" }, set: { metadata[keyPath: path] = $0.isEmpty ? nil : $0 })
    }
    private func nextID(_ ids: [Int]) -> Int { min(ids.min() ?? 0, 0) - 1 }
    private func credits(_ label: String, entries: Binding<[MediaCredit]>) -> some View {
        Section {
            ForEach(entries) { $credit in
                VStack {
                    TextField("姓名", text: $credit.name)
                    TextField("角色／职务", text: $credit.role)
                    Button("删除", role: .destructive) { entries.wrappedValue.removeAll { $0.id == credit.id } }
                }
            }
            Button("添加") { entries.wrappedValue.append(MediaCredit(id: UUID().uuidString, name: "", role: "")) }
        } header: { Text(String(localized: String.LocalizationValue(label))) }
    }
    private func parts(_ label: String, entries: Binding<[MediaPart]>) -> some View {
        Section {
            ForEach(entries) { $part in
                DisclosureGroup(part.title.isEmpty ? String(localized: "未命名") : part.title) {
                    TextField("名称", text: $part.title)
                    TextField("序号", value: $part.number, format: .number).keyboardType(.numberPad)
                    TextField("日期", text: Binding(get: { part.date ?? "" }, set: { part.date = $0.isEmpty ? nil : $0 }))
                    TextField("简介", text: Binding(get: { part.overview ?? "" }, set: { part.overview = $0.isEmpty ? nil : $0 }), axis: .vertical)
                    TextField("集数", value: $part.episodeCount, format: .number).keyboardType(.numberPad)
                    Button("删除", role: .destructive) { entries.wrappedValue.removeAll { $0.id == part.id } }
                }
            }
            Button("添加") { entries.wrappedValue.append(MediaPart(id: nextID(entries.wrappedValue.map(\.id)), number: 1, title: "")) }
        } header: { Text(String(localized: String.LocalizationValue(label))) }
    }
    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MetadataEditError.invalidTitle }
            func integer(_ field: MetadataField) throws -> Int? {
                let value = (numbers[field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if value.isEmpty { return nil }
                guard let number = Int(value), number >= 0 else { throw MetadataEditError.invalidNumber }
                return number
            }
            metadata.runtimeMinutes = try integer(.runtimeMinutes); metadata.episodeCount = try integer(.episodeCount)
            let ratingText = (numbers[.tmdbRating] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if ratingText.isEmpty { metadata.tmdbRating = nil }
            else {
                guard let rating = Double(ratingText), rating.isFinite, (0...10).contains(rating) else { throw MetadataEditError.invalidNumber }
                metadata.tmdbRating = rating
            }
            if let date = metadata.releaseDate, !date.isEmpty {
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
                guard let parsed = formatter.date(from: date), formatter.string(from: parsed) == date else { throw MetadataEditError.invalidDate }
            }
            item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            item.metadata = metadata
            try await onSave(item); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
private enum MetadataEditError: LocalizedError {
    case invalidTitle, invalidNumber, invalidDate
    var errorDescription: String? {
        switch self {
        case .invalidTitle: String(localized: "请填写片名。")
        case .invalidNumber: String(localized: "时长及集数需为非负整数，TMDb 评分需在 0–10 之间。")
        case .invalidDate: String(localized: "日期需为有效的 YYYY-MM-DD。")
        }
    }
}

private struct LocalArtworkPicker: View {
    let label: String
    let kind: String
    @Binding var data: Data?
    @State private var selection: PhotosPickerItem?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading) {
            if let data, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().frame(height: 100).accessibilityHidden(true) }
            PhotosPicker(selection: $selection, matching: .images) { Label(String(localized: String.LocalizationValue(label)), systemImage: "photo") }
            if data != nil { Button("移除图片", role: .destructive) { selection = nil; data = nil } }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .task(id: selection) {
            let selected = selection; error = nil
            guard let selected else { return }
            do {
                guard let bytes = try await selected.loadTransferable(type: Data.self) else { throw TMDbError.decoding }
                let role = kind
                let processed = try await Task.detached(priority: .utility) { try TMDbImagePipeline.process(bytes, pixels: role == "logo" ? 500 : 1280, kind: role) }.value
                guard !Task.isCancelled, selection == selected else { return }
                data = processed
            } catch {
                guard !Task.isCancelled, selection == selected else { return }
                self.error = String(localized: "图片读取失败，请重新选择。")
            }
        }
    }
}
