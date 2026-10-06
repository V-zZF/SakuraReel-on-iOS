import SwiftUI

struct SyncConflictRequest: Identifiable {
    let id = UUID()
    let conflicts: [SyncDeleteConflict]
}

@MainActor @Observable
final class LibrarySyncController {
    private(set) var isRunning = false
    private(set) var phase = ""
    private(set) var conflictRequest: SyncConflictRequest?
    var message: ResultMessage?
    private var prepared: LibrarySyncPreparation?
    struct ResultMessage { var title: String; var body: String }

    func start(repository: MediaRepository) {
        guard !isRunning else { return }
        isRunning = true; phase = "比较两端资料…"
        Task { await run(repository: repository) }
    }
    private func run(repository: MediaRepository, choices: [String: Bool] = [:], preparation: LibrarySyncPreparation? = nil) async {
        do {
            if let preparation {
                try await finish(preparation, choices: choices, repository: repository)
                return
            }
            // A stale preview is recomputed; deletion decisions are never applied to a new preview.
            for attempt in 0..<3 {
                do {
                    let result = try await SyncFolder.withAccess { folder in
                        try await repository.prepareSynchronization(remote: folder)
                    }
                    if !result.merged.conflicts.isEmpty {
                        prepared = result; phase = "等待处理删除冲突"
                        conflictRequest = SyncConflictRequest(conflicts: result.merged.conflicts)
                        return
                    }
                    try await finish(result, choices: [:], repository: repository)
                    return
                } catch LibrarySyncError.changed where attempt < 2 {
                    phase = "资料已变化，重新比较…"
                    await repository.load()
                }
            }
        } catch LibrarySyncError.changed where preparation != nil {
            phase = "资料已变化，重新比较…"
            await repository.load()
            await run(repository: repository)
        } catch {
            message = ResultMessage(title: "同步未完成", body: error.localizedDescription)
            isRunning = false; phase = ""; prepared = nil
        }
    }
    private func finish(_ preparation: LibrarySyncPreparation, choices: [String: Bool], repository: MediaRepository) async throws {
        let report = try await SyncFolder.withAccess { folder in
            guard folder.standardizedFileURL == preparation.remote.folder.standardizedFileURL else { throw LibrarySyncError.changed }
            return try await repository.commitSynchronization(preparation, choices: choices) { [weak self] stage in
                Task { @MainActor in if self?.isRunning == true { self?.phase = stage } }
            }
        }
        message = ResultMessage(title: "同步完成", body: report.description)
        isRunning = false; phase = ""; prepared = nil
    }
    func resolve(_ choices: [String: Bool], repository: MediaRepository) {
        guard let prepared, conflictRequest?.conflicts.allSatisfy({ choices[$0.id] != nil }) == true else { return }
        conflictRequest = nil; self.prepared = nil; phase = "准备同步…"
        Task { await run(repository: repository, choices: choices, preparation: prepared) }
    }
    func cancelConflict() {
        guard conflictRequest != nil else { return }
        conflictRequest = nil; prepared = nil; isRunning = false; phase = ""
    }
}

struct SyncConflictSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: SyncConflictRequest
    let onResolve: ([String: Bool]) -> Void
    @State private var choices: [String: Bool] = [:]
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("一端删除了作品，另一端修改了它。请选择保留或删除，确认前不会提交同步。")
                        .foregroundStyle(.secondary)
                }
                ForEach(request.conflicts) { conflict in
                    Section(conflict.entry.title) {
                        LabeledContent("修改时间", value: conflict.entry.updatedAt.formatted(date: .numeric, time: .shortened))
                        LabeledContent("删除时间", value: conflict.deletedAt.formatted(date: .numeric, time: .shortened))
                        LabeledContent("评分", value: "\(conflict.entry.rating)")
                        if let review = conflict.entry.review, !review.isEmpty { Text(review) }
                        Picker("处理方式", selection: Binding<Bool?>(get: { choices[conflict.id] }, set: { choices[conflict.id] = $0 })) {
                            Text("请选择").tag(Optional<Bool>.none)
                            Text("保留作品").tag(Optional(true))
                            Text("删除作品").tag(Optional(false))
                        }
                    }
                }
            }
            .navigationTitle("同步冲突")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认同步") { onResolve(choices); dismiss() }
                        .disabled(choices.count != request.conflicts.count)
                }
            }
            .tint(Constants.accentPink)
        }
    }
}
