//
//  TMDbImagePipeline.swift
//  SakuraReel
//
//  Created by OpenAI Codex on behalf of zzf on 2026/10/2.
//
import Foundation
import UIKit
import ImageIO
import CryptoKit

actor TMDbImagePipeline: TMDbImageLoading {
    private let memory = NSCache<NSString, NSData>()
    private let tasks = SharedTaskPool<Data>()
    private var memoryDates: [String: Date] = [:]
    private let folder: URL
    init(folder: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("TMDbImages")) {
        self.folder = folder
        memory.totalCostLimit = 32 * 1024 * 1024
    }
    func load(_ url: URL, pixels: Int, kind: String = "thumbnail") async throws -> Data {
        try Task.checkCancellation()
        guard url.scheme == "https" else { throw TMDbError.network }
        let key = SHA256.hash(data: Data("\(url.absoluteString)|\(pixels)|\(kind)|v1".utf8)).map { String(format: "%02x", $0) }.joined()
        if let date = memoryDates[key], Date().timeIntervalSince(date) < 7 * 86400, let cached = memory.object(forKey: key as NSString) { return cached as Data }
        let destination = folder.appendingPathComponent(key)
        let folder = self.folder
        let data = try await tasks.value(for: key) {
            // The pool's producer executes away from MainActor; no UIKit objects cross isolation.
            let manager = FileManager.default
            if let attrs = try? manager.attributesOfItem(atPath: destination.path),
               let date = attrs[.modificationDate] as? Date, Date().timeIntervalSince(date) < 7 * 86400,
               let data = try? Data(contentsOf: destination) { return data }
            let (bytes, response) = try await URLSession.shared.data(from: url)
            try Task.checkCancellation()
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
                  bytes.count < 30 * 1024 * 1024 else { throw TMDbError.network }
            let data = try Self.process(bytes, pixels: pixels, kind: kind)
            try Task.checkCancellation()
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            Self.trim(folder: folder)
            return data
        }
        try Task.checkCancellation()
        memory.setObject(data as NSData, forKey: key as NSString, cost: data.count)
        memoryDates[key] = Date()
        if memoryDates.count > 1000 { memoryDates = [key: Date()]; memory.removeAllObjects() }
        return data
    }
    nonisolated static func process(_ bytes: Data, pixels: Int, kind: String) throws -> Data {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw TMDbError.decoding }
        let image = UIImage(cgImage: cg)
        let data: Data?
        if kind == "poster" { data = PosterResizer.resizedPosterData(from: image) }
        else if kind == "logo" { data = image.pngData() }
        else { data = image.jpegData(compressionQuality: 0.85) }
        guard let data else { throw TMDbError.decoding }
        return data
    }
    private nonisolated static func trim(folder: URL) {
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        let values = files.compactMap { url -> (URL, Int, Date)? in
            guard let value = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            return (url, value.fileSize ?? 0, value.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = values.reduce(0) { $0 + $1.1 }
        for (url, size, date) in values where total > 150 * 1024 * 1024 || Date().timeIntervalSince(date) > 7 * 86400 {
            if (try? manager.removeItem(at: url)) != nil { total -= size }
        }
    }
}
