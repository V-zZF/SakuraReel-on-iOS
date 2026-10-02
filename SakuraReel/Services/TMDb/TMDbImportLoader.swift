//
//  TMDbImportLoader.swift
//  SakuraReel
//
//  Created by OpenAI Codex on behalf of zzf on 2026/10/2.
//
import Foundation
import Observation

protocol TMDbImageLoading: Sendable {
    func load(_ url: URL, pixels: Int, kind: String) async throws -> Data
}

struct TMDbImportLoader: Sendable {
    let service: any TMDbServing
    let images: any TMDbImageLoading
    func load(_ source: MediaSource) async throws -> TMDbImportDraft {
        var draft = try await service.details(source)
        let paths = (draft.metadata.posterPath, draft.metadata.backdropPath, draft.metadata.logoPath)
        async let poster = image(paths.0, role: "poster", pixels: 900)
        async let backdrop = image(paths.1, role: "backdrop", pixels: 1280)
        async let logo = image(paths.2, role: "logo", pixels: 500)
        let results = await (poster, backdrop, logo)
        try Task.checkCancellation()
        draft.poster = results.0; draft.backdrop = results.1; draft.logo = results.2
        if draft.metadata.posterPath != nil && draft.poster == nil { draft.warnings.append(String(localized: "海报下载失败，可重试海报或继续导入文本。")) }
        if draft.metadata.backdropPath != nil && draft.backdrop == nil { draft.warnings.append(String(localized: "背景图下载失败，将使用本地海报。")) }
        if draft.metadata.logoPath != nil && draft.logo == nil { draft.warnings.append(String(localized: "Logo 下载失败，将显示片名。")) }
        return draft
    }
    func image(_ path: String?, role: String, pixels: Int) async -> Data? {
        guard let path, let url = await service.imageURL(path, role: role, width: role == "poster" ? 780 : pixels) else { return nil }
        return try? await images.load(url, pixels: pixels, kind: role)
    }
}

/// Latest-selection state is shared by remote thumbnails and covered without UIKit.
@MainActor @Observable final class RemoteArtworkModel {
    private(set) var data: Data?
    private var requestID = UUID()
    func load(path: String?, role: String, pixels: Int, cachedConfiguration: Bool = false, service: any TMDbServing, images: any TMDbImageLoading) async {
        requestID = UUID(); let id = requestID; data = nil
        guard let path else { return }
        let resolved = cachedConfiguration ? await service.cachedImageURL(path, role: role, width: pixels) : await service.imageURL(path, role: role, width: pixels)
        guard let url = resolved else { return }
        let bytes = try? await images.load(url, pixels: pixels * 2, kind: "thumbnail")
        guard !Task.isCancelled, id == requestID else { return }
        data = bytes
    }
}
