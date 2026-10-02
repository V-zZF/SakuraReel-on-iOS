//
//  MediaDetailView.swift
//  SakuraReel
//
//  Created by OpenAI Codex on behalf of zzf on 2026/10/2.
//
import SwiftUI
import ImageIO

struct MediaDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MediaRepository.self) private var repository
    let itemID: UUID
    @State private var deletedInEditor = false
    @State private var editing = false
    @State private var editingMetadata = false
    @State private var deletion = false
    @State private var settings = false
    @State private var refreshing = false
    @State private var refreshTask: Task<Void, Never>?
    @State private var refreshID = UUID()
    @State private var imported: PresentedImport?
    @State private var error: String?
    @State private var headerShowsArtwork = true
    private var leftButtonColor: Color { !headerShowsArtwork || headerContrast.leftIsLight ? .black : .white }
    private var rightButtonColor: Color { !headerShowsArtwork || headerContrast.rightIsLight ? .black : .white }
    @State private var headerContrast = HeaderButtonContrast(leftIsLight: true, rightIsLight: true)
    @State private var hydratedItem: MediaItem?
    @State private var hydratedRevision: UInt64?
    private var item: MediaItem? {
        guard let current = repository.items.first(where: { $0.id == itemID }) else { return nil }
        return hydratedRevision == repository.document.revision ? hydratedItem ?? current : current
    }
    var body: some View {
        NavigationStack {
            Group {
                if let item {
                    ScrollView {
                        VStack(spacing: 20) {
                            hero(item)
                            VStack(alignment: .leading, spacing: 24) {
                                actions(item)
                                personal(item)
                                if let metadata = item.metadata {
                                    statistics(metadata)
                                    if let overview = metadata.overview, !overview.isEmpty {
                                        VStack(alignment: .leading, spacing: 8) { Text("简介").font(.title3.bold()); Text(overview).textSelection(.enabled) }
                                    }
                                    credits("演员", entries: metadata.cast)
                                    credits("职员", entries: metadata.crew)
                                    parts("季度", entries: metadata.seasons, role: "poster")
                                    parts("单集", entries: metadata.episodes, role: "still")
                                }
                                if refreshing { ProgressView("正在重新获取资料") }
                                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                            }.padding(.horizontal).padding(.bottom, 32).frame(maxWidth: 1000).frame(maxWidth: .infinity)
                        }
                    }
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        geometry.contentOffset.y + geometry.contentInsets.top < 250
                    } action: { _, showsArtwork in headerShowsArtwork = showsArtwork }
                    .ignoresSafeArea(edges: .top)
                } else { ContentUnavailableView("作品已不存在", systemImage: "film") }
            }
            .background(Constants.libraryBackground)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .tint(rightButtonColor)
                        .foregroundStyle(rightButtonColor)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("编辑个人记录", systemImage: "pencil") { editing = true }.disabled(hydratedItem == nil || hydratedRevision != repository.document.revision)
                        Button("编辑作品资料", systemImage: "doc.text") { editingMetadata = true }.disabled(hydratedItem == nil || hydratedRevision != repository.document.revision)
                        if item?.source != nil { Button("重新获取 TMDb 资料", systemImage: "arrow.clockwise") { refresh() }.disabled(refreshing) }
                        Button("TMDb 设置", systemImage: "gearshape") { settings = true }
                        Button("删除", systemImage: "trash", role: .destructive) { deletion = true }
                    } label: { Label("更多操作", systemImage: "ellipsis.circle") }
                    .tint(leftButtonColor)
                    .foregroundStyle(leftButtonColor)
                }
            }
            .sheet(isPresented: $editing, onDismiss: { if deletedInEditor { dismiss() } }) {
                if let item { AddEditMediaView(initialItem: item, onSave: { try await repository.upsert($0) }, onDelete: { try await repository.remove(item); deletedInEditor = true }) }
            }
            .sheet(isPresented: $editingMetadata) {
                if let item { MediaMetadataEditor(initialItem: item) { try await saveMetadata($0) } }
            }
            .sheet(isPresented: $settings) { TMDbSettingsView() }
            .sheet(item: $imported) { selection in
                if let item {
                    TMDbImportPreview(draft: selection.draft, existing: item) { draft, fields in
                        try await repository.applyMetadata(draft, fields: fields, to: itemID)
                    }
                }
            }
            .alert("确认删除", isPresented: $deletion) {
                Button("删除", role: .destructive) { delete() }; Button("取消", role: .cancel) {}
            } message: { Text("删除后不可恢复，确定要删除吗？") }
            .task(id: repository.document.revision) {
                let requestedRevision = repository.document.revision
                do {
                    let loaded = try await repository.editingItem(for: itemID)
                    guard !Task.isCancelled, requestedRevision == repository.document.revision else { return }
                    hydratedItem = loaded; hydratedRevision = repository.document.revision
                }
                catch { self.error = error.localizedDescription }
            }
            .onDisappear { refreshTask?.cancel(); refreshID = UUID(); refreshing = false }
            .onChange(of: TMDbEnvironment.shared.settings.generation) { refreshTask?.cancel(); refreshID = UUID(); refreshing = false }
            .tint(Constants.accentPink)
        }
    }
    private func hero(_ item: MediaItem) -> some View {
        GeometryReader { geometry in
        ZStack(alignment: .bottom) {
            if let bytes = item.backdrop ?? item.poster, let image = UIImage(data: bytes) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: 370).clipped().accessibilityHidden(true)
            } else { Color(.systemGray5) }
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 8) {
                if let bytes = item.logo, let logo = UIImage(data: bytes) {
                    Image(uiImage: logo).resizable().scaledToFit().frame(maxWidth: 280, maxHeight: 80).accessibilityLabel(item.title)
                } else { Text(item.title).font(.largeTitle.bold()).multilineTextAlignment(.center) }
                if let season = item.metadata?.seasonTitle { Text(season).font(.headline) }
                Text([item.metadata?.releaseDate, item.metadata?.episodeCount.map { String(localized: "\($0) 集") }, item.metadata?.statusLabel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                if let genres = item.metadata?.genres, !genres.isEmpty { Text(genres.joined(separator: " · ")).font(.caption) }
            }.foregroundStyle(.white).padding(.horizontal, 24).padding(.bottom, 26).padding(.top, 100)
        }.frame(width: geometry.size.width, height: 370).clipped()
        .task(id: HeaderArtworkIdentity(data: item.backdrop ?? item.poster, width: geometry.size.width)) {
            let data = item.backdrop ?? item.poster
            let width = geometry.size.width
            let contrast = await Task.detached(priority: .utility) {
                HeaderButtonContrast.sample(data: data, displayWidth: width)
            }.value
            guard !Task.isCancelled else { return }
            headerContrast = contrast
        }
        }.frame(height: 370)
    }
    private func actions(_ item: MediaItem) -> some View {
        HStack(spacing: 16) {
            if let url = externalURL(item.metadata?.homepage) { Button { UIApplication.shared.open(url) } label: { Label("官网", systemImage: "globe") } }
            if let url = externalURL(item.playURL) { Button { UIApplication.shared.open(url) } label: { Label("播放", systemImage: "play.fill") } }
            ShareLink(item: item.title + (item.source?.webpage.map { "\n" + $0.absoluteString } ?? "")) { Label("分享", systemImage: "square.and.arrow.up") }
        }.buttonStyle(.bordered).controlSize(.small)
    }
    private func personal(_ item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("个人记录").font(.title3.bold()); Spacer(); Button("编辑") { editing = true }.disabled(hydratedItem == nil || hydratedRevision != repository.document.revision) }
            HStack {
                RatingLabel(rating: item.rating)
                Text(item.status.displayName)
                Spacer()
                if let year = item.watchYear, let month = item.watchMonth { Text("\(String(year)) 年 \(month) 月").foregroundStyle(.secondary) }
            }
            if let review = item.review, !review.isEmpty { Text(review).textSelection(.enabled) }
            else { Text("暂无短评").foregroundStyle(.secondary) }
        }.padding().background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
    private func statistics(_ metadata: MediaMetadata) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let score = metadata.tmdbRating { stat("TMDb 评分", value: String(format: "%.1f / 10", score), symbol: "star") }
            if let runtime = metadata.runtimeMinutes { stat("时长", value: String(localized: "\(runtime) 分钟"), symbol: "clock") }
            if let count = metadata.episodeCount { stat("集数", value: String(localized: "\(count) 集"), symbol: "tv") }
            if !metadata.companies.isEmpty { stat("制作公司", value: metadata.companies.map(\.name).joined(separator: "、"), symbol: "building.2") }
        }
    }
    private func stat(_ label: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: String.LocalizationValue(label)), systemImage: symbol)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.headline).lineLimit(3, reservesSpace: true).truncationMode(.tail)
                .textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
    @ViewBuilder private func credits(_ label: String, entries: [MediaCredit]) -> some View {
        if !entries.isEmpty {
            let showsPhotos = entries.contains { !($0.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: String.LocalizationValue(label))).font(.title3.bold())
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(entries) { credit in
                            VStack(alignment: .leading, spacing: 5) {
                                if showsPhotos {
                                    TMDbRemoteImage(path: credit.imagePath, role: "profile", width: 185, cachedConfiguration: true)
                                        .frame(width: 88, height: 120).clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                Text(credit.name).font(.caption.bold()); Text(credit.role).font(.caption).foregroundStyle(.secondary)
                            }.frame(width: 88, alignment: .leading)
                        }
                    }
                }
            }
        }
    }
    @ViewBuilder private func parts(_ label: String, entries: [MediaPart], role: String) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: String.LocalizationValue(label))).font(.title3.bold())
                ForEach(entries) { part in
                    DisclosureGroup {
                        if let overview = part.overview, !overview.isEmpty { Text(overview).font(.subheadline).padding(.vertical, 8) }
                        if let count = part.episodeCount { Text("\(count) 集").font(.caption) }
                    } label: {
                        HStack {
                            TMDbRemoteImage(path: part.imagePath, role: role, cachedConfiguration: true).frame(width: 45, height: 60).clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading) { Text(part.title); if let date = part.date { Text(date).font(.caption).foregroundStyle(.secondary) } }
                        }
                    }
                }
            }
        }
    }
    private func externalURL(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme != "javascript", scheme != "data", scheme != "file" else { return nil }
        return url
    }
    private func saveMetadata(_ edited: MediaItem) async throws {
        guard var current = item else { throw TMDbError.notFound }
        current.title = edited.title; current.metadata = edited.metadata
        current.poster = edited.poster; current.backdrop = edited.backdrop; current.logo = edited.logo
        current.attachments = edited.attachments
        try await repository.upsert(current)
    }
    private func delete() {
        guard let item else { return }
        Task { do { try await repository.remove(item); dismiss() } catch { self.error = error.localizedDescription } }
    }
    private func refresh() {
        guard var source = item?.source else { return }
        source.language = TMDbEnvironment.shared.settings.language
        refreshTask?.cancel(); refreshID = UUID(); let id = refreshID
        refreshing = true; error = nil
        refreshTask = Task {
            do {
                let environment = TMDbEnvironment.shared
                await environment.service.invalidateDetails()
                let draft = try await TMDbImportLoader(service: environment.service, images: environment.images).load(source)
                guard !Task.isCancelled, id == refreshID else { return }
                imported = PresentedImport(draft: draft)
            } catch {
                guard !Task.isCancelled, id == refreshID else { return }
                self.error = error.localizedDescription
            }
            refreshing = false
        }
    }
}


private struct HeaderArtworkIdentity: Hashable {
    let data: Data?
    let width: CGFloat
}

/// Samples the visible hero's upper corners off the main thread, including its dark overlay.
private struct HeaderButtonContrast: Sendable {
    let leftIsLight: Bool
    let rightIsLight: Bool

    nonisolated static func sample(data: Data?, displayWidth: CGFloat) -> Self {
        guard displayWidth > 0, let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return Self(leftIsLight: true, rightIsLight: true) }
        let width = 64
        let height = max(1, Int(ceil(120 / displayWidth * CGFloat(width))))
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let sampled = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // UIKit-style top-origin coordinates match the hero's center aspect-fill crop.
            context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
            let heroHeight = 370 / displayWidth * CGFloat(width)
            let scale = max(CGFloat(width) / CGFloat(image.width), heroHeight / CGFloat(image.height))
            let drawnWidth = CGFloat(image.width) * scale, drawnHeight = CGFloat(image.height) * scale
            context.draw(image, in: CGRect(x: (CGFloat(width) - drawnWidth) / 2,
                                          y: (heroHeight - drawnHeight) / 2,
                                          width: drawnWidth, height: drawnHeight))
            return true
        }
        guard sampled else { return Self(leftIsLight: true, rightIsLight: true) }
        func isLight(_ columns: Range<Int>) -> Bool {
            var luminance = 0.0
            for y in 0..<height {
                for x in columns {
                    let offset = (y * width + x) * 4
                    func linear(_ channel: UInt8) -> Double {
                        let value = Double(channel) / 255 * 0.85
                        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
                    }
                    luminance += 0.2126 * linear(pixels[offset]) + 0.7152 * linear(pixels[offset + 1]) + 0.0722 * linear(pixels[offset + 2])
                }
            }
            return luminance / Double(height * columns.count) > 0.179
        }
        return Self(leftIsLight: isLight(0..<20), rightIsLight: isLight(44..<64))
    }
}
