// Layout adapted from AniShelf, Copyright 2024 Samuel He (Apache-2.0).
// Modified for SakuraReel on 2026-10-02. See Resources/ThirdPartyNotices.txt.
import SwiftUI

struct MediaDetailTracking: View {
    @Binding var record: PersonalRecord
    @State private var expanded = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var year: Binding<Int?> {
        Binding(get: { record.watchedAt?.year }, set: { value in
            record.watchedAt = value.map { YearMonth(year: $0, month: record.watchedAt?.month ?? Calendar.current.component(.month, from: Date())) }
        })
    }
    private var month: Binding<Int?> {
        Binding(get: { record.watchedAt?.month }, set: { value in
            if let value, let year = record.watchedAt?.year { record.watchedAt = YearMonth(year: year, month: value) }
        })
    }
    private var review: Binding<String> {
        Binding(get: { record.review ?? "" }, set: { record.review = $0.isEmpty ? nil : $0 })
    }
    private var playURL: Binding<String> {
        Binding(get: { record.playURL ?? "" }, set: { record.playURL = $0.isEmpty ? nil : $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("评分", systemImage: "star").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button("清除") { record.rating = 0 }
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary).disabled(record.rating == 0)
                }
                HStack(spacing: 14) {
                    ForEach(1...5, id: \.self) { star in
                        ratingStar(star)
                    }
                }.frame(maxWidth: .infinity).padding(.vertical, 8)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: record.rating)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("个人评分")
                .accessibilityValue(record.rating == 0 ? "未评分" : "\(record.rating) 分，满分 10 分")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: record.rating = min(10, record.rating + 1)
                    case .decrement: record.rating = max(0, record.rating - 1)
                    @unknown default: break
                    }
                }
            }
            Divider()
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checklist").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Text("追踪").font(.title3.bold())
                    Spacer()
                    Image(systemName: "chevron.down").font(.footnote.bold()).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }.contentShape(Rectangle())
            }.buttonStyle(LibraryPressStyle()).accessibilityValue(expanded ? "已展开" : "已折叠")
            if expanded { editor }
        }
        .padding(18).modifier(MediaDetailPanel())
    }

    private func ratingStar(_ star: Int) -> some View {
        let full = star * 2
        let symbol = record.rating >= full ? "star.fill" : record.rating == full - 1 ? "star.leadinghalf.filled" : "star"
        return Image(systemName: symbol)
            .font(.system(size: 24))
            .foregroundStyle(record.rating >= full - 1 ? RatingColor.color(for: record.rating) : Color.secondary.opacity(0.6))
            .frame(maxWidth: .infinity).frame(height: 44)
            .overlay {
                HStack(spacing: 0) {
                    Button { record.rating = full - 1 } label: { Color.clear.contentShape(Rectangle()) }
                    Button { record.rating = full } label: { Color.clear.contentShape(Rectangle()) }
                }.buttonStyle(.plain)
            }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("观看状态").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Picker("观看状态", selection: $record.status) {
                ForEach(MediaStatus.allCases) { status in Text(status.displayName).tag(status) }
            }.pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 10) {
                Text("观看年月").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                YearMonthPickers(year: year, month: month).pickerStyle(.menu)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("短评").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextEditor(text: review)
                    .frame(height: 180).scrollContentBackground(.hidden).padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .topLeading) {
                        if review.wrappedValue.isEmpty {
                            Text("写下观影感想…").foregroundStyle(.tertiary).padding(.horizontal, 17).padding(.vertical, 20).allowsHitTesting(false)
                        }
                    }.accessibilityLabel("短评")
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("播放链接").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextField("https://", text: playURL).keyboardType(.URL).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().textFieldStyle(.roundedBorder).accessibilityLabel("播放链接")
            }
        }
    }
}

/// Own the draft inside the editing sheet; the detail itself remains read-only.
struct MediaDetailPersonalEditor: View {
    private var dismiss = LibraryPopupDismiss()
    let onClose: (() -> Void)?
    let initialRecord: PersonalRecord
    let onSave: (PersonalRecord) async throws -> Void
    @State private var record: PersonalRecord
    @State private var saving = false
    @State private var confirmDiscard = false
    @State private var saveError: String?

    init(initialRecord: PersonalRecord, onClose: (() -> Void)? = nil, onSave: @escaping (PersonalRecord) async throws -> Void) {
        self.onClose = onClose
        self.initialRecord = initialRecord
        self.onSave = onSave
        _record = State(initialValue: initialRecord)
    }

    private func close() { if let onClose { onClose() } else { dismiss() } }

    private var isDirty: Bool { record != initialRecord }

    var body: some View {
        NavigationStack {
            ScrollView {
                MediaDetailTracking(record: $record).padding(16)
                    .frame(maxWidth: 700).frame(maxWidth: .infinity)
            }
            .background(Constants.libraryBackground)
            .navigationTitle("编辑个人记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        if isDirty { confirmDiscard = true } else { close() }
                    }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(saving)
                }
            }
            .disabled(saving)
            .overlay { if saving { ProgressView("正在保存").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .confirmationDialog("有未保存的修改", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { close() }
                Button("继续编辑", role: .cancel) {}
            }
            .alert("无法保存", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("好", role: .cancel) { saveError = nil }
            } message: { Text(saveError ?? "") }
            .tint(Constants.accentPink)
        }
        .interactiveDismissDisabled(isDirty || saving)
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.light)
    }

    private func save() {
        guard !saving else { return }
        guard isDirty else { close(); return }
        let draft = record
        saving = true
        Task {
            do { try await onSave(draft); close() }
            catch { saveError = error.localizedDescription }
            saving = false
        }
    }
}
