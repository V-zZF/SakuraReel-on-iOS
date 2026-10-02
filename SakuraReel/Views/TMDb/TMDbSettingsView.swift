//
//  TMDbSettingsView.swift
//  SakuraReel
//
//  Created by OpenAI Codex on behalf of zzf on 2026/10/2.
//
import SwiftUI

struct TMDbSettingsView: View {
    var onSaved: (() -> Void)? = nil
    var onSkip: (() throws -> Void)? = nil
    var onManualAdd: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    private let environment = TMDbEnvironment.shared
    @State private var language = "zh-CN"
    @State private var originalLanguage = "zh-CN"
    @State private var key = ""
    @State private var proxy = ""
    @State private var usesProxy = false
    @State private var usesAniShelf = true
    @State private var message: String?
    @State private var validating = false
    @State private var task: Task<Void, Never>?
    @State private var requestID = UUID()
    @State private var initialized = false
    @State private var originalKey = ""
    @State private var originalProxy = ""
    @State private var originalUsesProxy = false
    @State private var discard = false
    private var dirty: Bool { language != originalLanguage || key != originalKey || proxy != originalProxy || usesProxy != originalUsesProxy || (usesProxy && (usesAniShelf != TMDbRoutes.aniShelf.contains(originalProxy))) }
    var body: some View {
        let settings = environment.settings
        NavigationStack {
            Form {
                Section("鉴权") {
                    SecureField("TMDb API Key（v3）", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("删除 Key", role: .destructive) { key = "" }
                    Text("Key 仅保存在本机 Keychain，不进入收藏库或导出文件。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let onSkip {
                    Section {
                        Button("跳过，使用默认 API（不稳定）") {
                            do { invalidate(); try onSkip() }
                            catch { message = error.localizedDescription }
                        }
                        if let onManualAdd {
                            Button("手动添加", systemImage: "square.and.pencil") { invalidate(); onManualAdd() }
                        }
                        Text("也可以稍后在 TMDb 设置中填写自己的 API Key。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("元数据") {
                    Picker("语言", selection: $language) {
                        ForEach(TMDbSettings.languages, id: \.0) { Text($0.1).tag($0.0) }
                    }
                }
                Section("连接线路") {
                    Toggle("使用 API 代理", isOn: $usesProxy)
                    if usesProxy {
                        Picker("代理方案", selection: $usesAniShelf) {
                            Text("AniShelf 代理").tag(true)
                            Text("自定义代理").tag(false)
                        }
                        if usesAniShelf {
                            Text("使用 tmdb-api.konakona.dev；连接失败时尝试 tmdb-api.konakona52.com。")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            TextField("https://你的 API 主机", text: $proxy)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        }
                        Text("API 请求和 Key 会经过所选代理。AniShelf 代理由第三方运营，图片仍直连 TMDb CDN。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else { Text("直连 api.themoviedb.org；连接失败可开启 AniShelf 代理。") }
                    Button("验证当前线路") { validate() }.disabled(validating || key.isEmpty)
                    if validating { ProgressView("验证中") }
                    if let message { Text(message).font(.footnote).accessibilityLabel(message) }
                }
                Section("关于 TMDb") {
                    Image("TMDbAttribution").resizable().scaledToFit().frame(width: 110, height: 32).accessibilityLabel("TMDb")
                    Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                        .font(.caption)
                    DisclosureGroup("开源说明") {
                        Text((try? String(contentsOf: Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt") ?? URL(fileURLWithPath: "/missing-notices"), encoding: .utf8)) ?? "AniShelf — Copyright 2024 Samuel He, Apache 2.0")
                            .font(.caption).textSelection(.enabled)
                    }
                    Link("The Movie Database", destination: URL(string: "https://www.themoviedb.org")!)
                    Text("仅在搜索、导入或主动重新获取时联网。作品资料保存后可自行修改。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("TMDb 设置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { if dirty { discard = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") {
                    do { if onSaved != nil && key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            message = String(localized: "请填写 API Key，或选择跳过。")
                            return
                        }
                        try settings.save(key: key, proxy: usesProxy ? (usesAniShelf ? TMDbRoutes.aniShelf[0] : proxy) : nil)
                        settings.language = language
                        invalidate()
                        if let onSaved { onSaved() } else { dismiss() } }
                    catch { message = error.localizedDescription }
                } }
            }
            .onAppear {
                guard !initialized else { return }; initialized = true
                language = settings.language; originalLanguage = language
                key = settings.connection.key; usesProxy = settings.host != "api.themoviedb.org"
                proxy = usesProxy ? settings.host : ""
                usesAniShelf = !usesProxy || TMDbRoutes.aniShelf.contains(settings.host)
                originalKey = key; originalProxy = proxy; originalUsesProxy = usesProxy
            }
            .onChange(of: key) { invalidate() }.onChange(of: proxy) { invalidate() }.onChange(of: usesProxy) { invalidate() }.onChange(of: usesAniShelf) { invalidate() }
            .onDisappear { task?.cancel() }
            .modifier(UnsavedDismissGuard(isDirty: dirty, onAttempt: { discard = true }))
            .alert("放弃修改？", isPresented: $discard) {
                Button("放弃修改", role: .destructive) { dismiss() }; Button("继续编辑", role: .cancel) {}
            }
            .tint(Constants.accentPink)
        }
    }
    private func invalidate() { requestID = UUID(); task?.cancel(); validating = false; message = nil }
    private func validate() {
        invalidate()
        let id = requestID
        do {
            let host = try TMDbSettings.validatedHost(usesProxy ? (usesAniShelf ? TMDbRoutes.aniShelf[0] : proxy) : nil)
            let connection = TMDbConnection(key: key.trimmingCharacters(in: .whitespacesAndNewlines), host: host, generation: UUID(),
                fallbackHosts: usesProxy && usesAniShelf ? TMDbRoutes.aniShelf.filter { $0 != host } : [])
            validating = true
            task = Task {
                do {
                    try await environment.service.validate(connection)
                    guard !Task.isCancelled, id == requestID else { return }
                    message = String(localized: "连接成功，API Key 有效。")
                } catch {
                    guard !Task.isCancelled, id == requestID else { return }
                    message = error.localizedDescription
                }
                validating = false
            }
        } catch { message = error.localizedDescription }
    }
}
