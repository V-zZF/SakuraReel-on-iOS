//
//  TMDbSearchModel.swift
//  SakuraReel
//
//  Created by OpenAI Codex on behalf of zzf on 2026/10/2.
//
import Foundation
import Observation

@MainActor @Observable final class TMDbSearchModel {
    struct Group {
        var results: [TMDbSearchResult] = []
        var page = 0
        var totalPages = 0
        var loading = false
        var error: String?
    }
    private(set) var movies = Group()
    private(set) var series = Group()
    private(set) var requestID = UUID()
    private var query = ""
    private var language = "zh-CN"
    private let service: any TMDbServing
    init(service: any TMDbServing) { self.service = service }
    func invalidate() { requestID = UUID(); movies = Group(); series = Group() }
    func search(query: String, language: String, type: String) async {
        invalidate()
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines); self.language = language
        guard !self.query.isEmpty else { return }
        let id = requestID
        do { try await Task.sleep(for: .milliseconds(300)); try Task.checkCancellation() } catch { return }
        await withTaskGroup(of: Void.self) { group in
            if type != "movie" { group.addTask { await self.load(.series, id: id) } }
            if type != "series" { group.addTask { await self.load(.movie, id: id) } }
        }
    }
    func load(_ type: TMDbMediaType, id: UUID? = nil) async {
        let identity = id ?? requestID
        let current = type == .movie ? movies : series
        guard identity == requestID, !current.loading, current.page == 0 || current.page < current.totalPages else { return }
        set(type) { $0.loading = true; $0.error = nil }
        do {
            let page = try await service.search(query, type: type, language: language, page: current.page + 1)
            guard identity == requestID else { return }
            if Task.isCancelled { set(type) { $0.loading = false }; return }
            set(type) {
                var seen = Set($0.results.map(\.id))
                $0.results.append(contentsOf: page.results.filter { seen.insert($0.id).inserted })
                $0.page = page.page; $0.totalPages = page.totalPages; $0.loading = false
            }
        } catch {
            guard identity == requestID else { return }
            set(type) { $0.loading = false; $0.error = Task.isCancelled || error is CancellationError ? nil : error.localizedDescription }
        }
    }
    private func set(_ type: TMDbMediaType, update: (inout Group) -> Void) {
        if type == .movie { update(&movies) } else { update(&series) }
    }
}
