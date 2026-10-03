import SwiftUI

struct MediaDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var dismiss = LibraryPopupDismiss()
    @Environment(MediaRepository.self) private var repository
    let itemID: UUID
    @State private var editingMetadata = false
    @State private var deletion = false
    @State private var settings = false
    @State private var refreshing = false
    @State private var refreshTask: Task<Void, Never>?
    @State private var refreshID = UUID()
    @State private var imported: PresentedImport?
    @State private var error: String?
    @State private var hydratedItem: MediaItem?
    @State private var hydratedRevision: UInt64?
    @State private var personalEditor: PersonalEditorSelection?
    @State private var saving = false
    private let episodesTarget = "detailEpisodes"
    private var isMac: Bool { ProcessInfo.processInfo.isiOSAppOnMac }
    private var showsMacEditor: Bool { isMac && (personalEditor != nil || editingMetadata) }
    private var personalSheet: Binding<PersonalEditorSelection?> {
        Binding(get: { isMac ? nil : personalEditor }, set: { personalEditor = $0 })
    }
    private var metadataSheet: Binding<Bool> {
        Binding(get: { !isMac && editingMetadata }, set: { editingMetadata = $0 })
    }

    private var item: MediaItem? {
        guard let current = repository.items.first(where: { $0.id == itemID }) else { return nil }
        if hydratedRevision == repository.document.revision { return hydratedItem ?? current }
        // Keep decoded artwork visible during revision hydration, using current metadata.
        var display = current
        let manifest = current.attachments
        if manifest == hydratedItem?.attachments {
            display.poster = hydratedItem?.poster
            display.backdrop = hydratedItem?.backdrop
            display.logo = hydratedItem?.logo
            display.attachments = manifest
        }
        return display
    }
    private var canEditMetadata: Bool { hydratedItem != nil && hydratedRevision == repository.document.revision && !saving }

    var body: some View {
        NavigationStack {
            Group {
                if let item {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 0) {
                                MediaDetailHeader(item: item)
                                VStack(alignment: .leading, spacing: 20) {
                                    actions(item).padding(.top, -20).padding(.bottom, 4)
                                    MediaDetailStatistics(item: item) {
                                        personalEditor = PersonalEditorSelection(record: item.personal)
                                    }.disabled(saving)
                                    Button {
                                        personalEditor = PersonalEditorSelection(record: item.personal)
                                    } label: {
                                        MediaDetailSection(title: "短评", symbol: "text.bubble") {
                                            Text(item.review.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? "暂无短评")
                                                .font(.body).lineSpacing(4)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }.contentShape(Rectangle())
                                    }.buttonStyle(LibraryPressStyle()).disabled(saving)
                                        .accessibilityElement(children: .combine)
                                        .accessibilityHint("编辑个人记录")
                                    MediaDetailSection(title: "简介", symbol: "text.alignleft") {
                                        Text(item.metadata?.overview.flatMap { $0.isEmpty ? nil : $0 } ?? "暂无简介")
                                            .font(.body).lineSpacing(4).textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    if let metadata = item.metadata {
                                        MediaDetailWorkStatistics(metadata: metadata, type: item.source?.mediaType,
                                            onEpisodes: metadata.episodes.isEmpty ? nil : {
                                                withAnimation(.spring(response: 0.6, dampingFraction: 0.86)) {
                                                    proxy.scrollTo(episodesTarget, anchor: .top)
                                                }
                                            })
                                        credits("演员", entries: metadata.cast)
                                        credits("职员", entries: metadata.crew)
                                        parts("季度", entries: metadata.seasons, role: "poster")
                                        parts("单集", entries: metadata.episodes, role: "still").id(episodesTarget)
                                    }
                                    if refreshing { ProgressView("正在重新获取资料") }
                                    if saving { ProgressView("正在保存") }
                                    if let error { Text(error).foregroundStyle(.red).font(.footnote).textSelection(.enabled) }
                                }
                                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 40)
                                .frame(maxWidth: 1000).frame(maxWidth: .infinity)
                            }
                        }
                        .coordinateSpace(name: MediaDetailHeader.coordinateSpace)
                        .ignoresSafeArea(edges: .top)
                        .modifier(DetailScrollEdgeStyle())
                    }
                } else { ContentUnavailableView("作品已不存在", systemImage: "film") }
            }
            .background(Constants.libraryBackground)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.font(.headline.weight(.semibold)).tint(.primary)
                        .modifier(MediaDetailToolbarStyle())
                        .disabled(saving)
                }
            }
            .librarySheet(item: personalSheet) { selection in
                MediaDetailPersonalEditor(initialRecord: selection.record) { record in
                    try await repository.updatePersonalRecord(record, for: itemID)
                }.environment(repository)
            }
            .librarySheet(isPresented: metadataSheet) {
                if let item { MediaMetadataEditor(initialItem: item) { try await saveMetadata($0) } }
            }
            .librarySheet(isPresented: $settings) { TMDbSettingsView() }
            .librarySheet(item: $imported) { selection in
                if let item {
                    TMDbImportPreview(draft: selection.draft, existing: item) { draft, fields in
                        try await repository.applyMetadata(draft, fields: fields, to: itemID)
                    }.environment(repository)
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
                    hydratedItem = loaded; hydratedRevision = requestedRevision
                } catch { self.error = error.localizedDescription }
            }
            .onDisappear { refreshTask?.cancel(); refreshID = UUID(); refreshing = false }
            .onChange(of: TMDbEnvironment.shared.settings.generation) { refreshTask?.cancel(); refreshID = UUID(); refreshing = false }
            .tint(Constants.accentPink)
        }
        .allowsHitTesting(!showsMacEditor)
        .accessibilityHidden(showsMacEditor)
        .overlay {
            ZStack {
                if showsMacEditor {
                    Color.black.opacity(0.12).ignoresSafeArea()
                        .transition(.opacity.animation(reduceMotion ? nil : .easeInOut(duration: 0.28)))
                }
                if showsMacEditor {
                    Group {
                        if let selection = personalEditor {
                            MediaDetailPersonalEditor(initialRecord: selection.record, onClose: { personalEditor = nil }) { record in
                                try await repository.updatePersonalRecord(record, for: itemID)
                            }
                        } else if editingMetadata, let item {
                            MediaMetadataEditor(initialItem: item, onClose: { editingMetadata = false }) {
                                try await saveMetadata($0)
                            }
                        }
                    }
                    .environment(repository)
                    .frame(maxWidth: 700, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
                    .padding(24)
                    .transition(editorTransition)
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.46, bounce: 0), value: showsMacEditor)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(saving || showsMacEditor)
        .preferredColorScheme(.light)
    }

    private var editorTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        return .asymmetric(
            insertion: .offset(y: 64)
                .combined(with: .scale(scale: 0.985, anchor: .bottom))
                .combined(with: .opacity)
                .animation(.spring(duration: 0.46, bounce: 0)),
            removal: .offset(y: 24)
                .combined(with: .opacity)
                .animation(.easeOut(duration: 0.22))
        )
    }

    private func actions(_ item: MediaItem) -> some View {
        Group {
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: 10) { actionButtons(item) }
            } else { actionButtons(item) }
        }
    }

    private func actionButtons(_ item: MediaItem) -> some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            if let url = item.source?.webpage ?? externalURL(item.metadata?.homepage) {
                Button { UIApplication.shared.open(url) } label: { MediaDetailActionIcon(symbol: "safari") }
                    .modifier(MediaDetailCircleStyle()).accessibilityLabel(item.source == nil ? "官网" : "TMDb 页面")
            }
            ShareLink(item: item.title + (item.source?.webpage.map { "\n" + $0.absoluteString } ?? "")) {
                MediaDetailActionIcon(symbol: "square.and.arrow.up")
            }.modifier(MediaDetailCircleStyle()).accessibilityLabel("分享")
            if let url = externalURL(item.playURL) {
                Button { UIApplication.shared.open(url) } label: { MediaDetailActionIcon(symbol: "play.fill") }
                    .modifier(MediaDetailCircleStyle()).accessibilityLabel("播放")
            }
            Menu {
                Button("编辑个人记录", systemImage: "pencil") {
                    personalEditor = PersonalEditorSelection(record: item.personal)
                }
                Button("编辑作品资料", systemImage: "doc.text") { editingMetadata = true }.disabled(!canEditMetadata)
                if item.source != nil {
                    Button("重新获取 TMDb 资料", systemImage: "arrow.clockwise") { refresh() }.disabled(refreshing || saving)
                }
                Button("TMDb 设置", systemImage: "gearshape") { settings = true }
                Button("删除", systemImage: "trash", role: .destructive) { deletion = true }.disabled(saving)
            } label: { MediaDetailActionIcon(symbol: "ellipsis") }
                .modifier(MediaDetailCircleStyle()).accessibilityLabel("更多操作")
            Spacer(minLength: 0)
        }.disabled(saving)
    }

    @ViewBuilder private func credits(_ label: String, entries: [MediaCredit]) -> some View {
        if !entries.isEmpty {
            let showsPhotos = entries.contains { !($0.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
            MediaDetailDisclosure(title: String(localized: String.LocalizationValue(label)), symbol: "person.2.fill") {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(entries) { credit in
                            VStack(alignment: .leading, spacing: 5) {
                                if showsPhotos {
                                    TMDbRemoteImage(path: credit.imagePath, role: "profile", width: 185, cachedConfiguration: true, placeholderColor: Constants.brandTitlePink)
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
            MediaDetailSection(title: String(localized: String.LocalizationValue(label)), symbol: "play.rectangle.on.rectangle.fill") {
                ForEach(entries) { part in
                    DisclosureGroup {
                        if let overview = part.overview, !overview.isEmpty { Text(overview).font(.subheadline).foregroundStyle(.black).padding(.vertical, 8) }
                        if let count = part.episodeCount { Text("\(count) 集").font(.caption).foregroundStyle(.black) }
                    } label: {
                        HStack {
                            TMDbRemoteImage(path: part.imagePath, role: role, cachedConfiguration: true, placeholderColor: Constants.brandTitlePink).frame(width: 45, height: 60).clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading) {
                                Text(part.title).foregroundColor(.black)
                                if let date = part.date {
                                    Text(date).font(.caption).foregroundStyle(Constants.brandTitlePink)
                                }
                            }
                        }
                    }
                    .tint(Constants.brandTitlePink)
                    .foregroundStyle(Constants.brandTitlePink)
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
        guard let item, !saving else { return }
        saving = true
        Task {
            do { try await repository.remove(item); dismiss() }
            catch { self.error = error.localizedDescription }
            saving = false
        }
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

private struct PersonalEditorSelection: Identifiable {
    let id = UUID()
    let record: PersonalRecord
}

/// The artwork stays clear beneath the native toolbar; button glass is independent.
private struct DetailScrollEdgeStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.scrollEdgeEffectHidden(true, for: .top)
        } else {
            content
        }
    }
}
