//
//  AddMediaFlowView.swift
//  SakuraReel
//
//  Created by OpenAI Codex on behalf of zzf on 2026/10/2.
//
import SwiftUI

/// Owns the unsaved item across onboarding, search and the existing manual form.
struct AddMediaFlowView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (MediaItem) async throws -> Void
    private enum Stage { case guidance, search, form }
    @State private var stage: Stage = TMDbEnvironment.shared.settings.hasKey ? .search : .guidance
    @State private var draft = MediaItem(title: "", status: .watched)
    @State private var error: String?
    @State private var apiKey = ""
    @State private var discardKey = false
    private var hasEnteredKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        Group {
            switch stage {
            case .guidance:
                guidance
            case .search:
                TMDbSearchView(existing: draft, onManualAdd: { stage = .form },
                               onImportFinished: { stage = .form }) { imported, fields in
                    draft = imported.merging(into: draft, fields: fields)
                }
            case .form:
                AddEditMediaView(initialItem: nil, initialDraft: draft, onSave: onSave, onDelete: nil)
            }
        }
        .tint(Constants.accentPink)
    }

    private var guidance: some View {
        NavigationStack {
            Form {
                Section {
                    Label("从 TMDb 快捷录入", systemImage: "film")
                        .font(.title2).accessibilityAddTraits(.isHeader)
                    Text("使用自己的 API Key 搜索电影和剧集。以下步骤均可跳过，也可以使用默认 API 后继续搜索。")
                        .foregroundStyle(.secondary)
                }
                Section("获取 API Key") {
                    Link("注册 TMDb", destination: URL(string: "https://www.themoviedb.org/signup")!)
                    Link("登录 TMDb", destination: URL(string: "https://www.themoviedb.org/login")!)
                    Link("获取 TMDb API", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                    Text("在 TMDb 网站申请 API Key（v3），然后返回填写。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    SecureField("TMDb API Key（v3）", text: $apiKey)
                        .font(.title3.monospaced())
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.asciiCapable).submitLabel(.go)
                        .privacySensitive()
                        .padding(14)
                        .background(Constants.accentPink.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Constants.accentPink, lineWidth: 2) }
                        .accessibilityLabel("TMDb API Key（v3）")
                        .onSubmit { saveKey() }
                    Button("保存并搜索", action: saveKey)
                        .buttonStyle(.borderedProminent).disabled(!hasEnteredKey)
                } header: {
                    Label("填写 API Key", systemImage: "key.fill")
                        .font(.headline).foregroundStyle(Constants.accentPink)
                } footer: {
                    Text("Key 仅保存在本机 Keychain，不进入收藏库或导出文件。")
                }
                Section {
                    Button("跳过，使用默认 API（不稳定）") {
                        do { try useDefaultKey() } catch { self.error = error.localizedDescription }
                    }
                    Button("手动添加", systemImage: "square.and.pencil") { stage = .form }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("TMDb 使用指引").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { if hasEnteredKey { discardKey = true } else { dismiss() } }
                }
            }
            .onChange(of: apiKey) { error = nil }
            .modifier(UnsavedDismissGuard(isDirty: hasEnteredKey, onAttempt: { discardKey = true }))
            .alert("放弃修改？", isPresented: $discardKey) {
                Button("放弃修改", role: .destructive) { dismiss() }
                Button("继续编辑", role: .cancel) {}
            }
        }
    }

    private func saveKey() {
        guard hasEnteredKey else { return }
        do {
            let settings = TMDbEnvironment.shared.settings
            try settings.save(key: apiKey, proxy: settings.host == "api.themoviedb.org" ? nil : settings.host)
            stage = .search
        } catch { self.error = error.localizedDescription }
    }

    private func useDefaultKey() throws {
        let settings = TMDbEnvironment.shared.settings
        try settings.useDefaultKey()
        stage = .search
    }
}
