//
//  TMDbSettings.swift
//  SakuraReel
//
//  Created by OpenAI Codex on behalf of zzf on 2026/10/2.
//
import Foundation
import Observation
import Security

enum TMDbKeychain {
    private static let service = "SakuraReel.TMDb"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "api-key"]
    }
    static func read() -> String {
        var query = query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ key: String) throws {
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var new = query
            new[kSecValueData as String] = data
            new[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(new as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess { throw KeychainError(status: status) }
    }
    private struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { String(localized: "无法保存 Keychain 凭据（\(status)）。") }
    }
}

@MainActor @Observable final class TMDbSettings {
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let persistKey: (String) throws -> Void
    var language: String { didSet { preferences.set(language, forKey: "tmdb.language") } }
    private(set) var host: String
    private(set) var generation = UUID()
    private var key: String
    static let languages = [("zh-CN", "简体中文"), ("zh-TW", "繁體中文"), ("en-US", "English"), ("ja-JP", "日本語")]
    init(preferences: UserDefaults = .standard,
         readKey: () -> String = TMDbKeychain.read,
         persistKey: @escaping (String) throws -> Void = TMDbKeychain.save) {
        self.preferences = preferences
        self.persistKey = persistKey
        language = preferences.string(forKey: "tmdb.language") ?? "zh-CN"
        host = preferences.string(forKey: "tmdb.host") ?? "api.themoviedb.org"
        key = readKey()
    }
    var hasKey: Bool { !key.isEmpty }
    var connection: TMDbConnection { TMDbConnection(key: key, host: host, generation: generation,
        fallbackHosts: TMDbRoutes.aniShelf.contains(host) ? TMDbRoutes.aniShelf.filter { $0 != host } : []) }
    func save(key: String, proxy: String?) throws {
        let selectedHost = try Self.validatedHost(proxy)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try persistKey(trimmed)
        self.key = trimmed; host = selectedHost; generation = UUID()
        preferences.set(host, forKey: "tmdb.host")
    }
    /// The optional local build credential is never part of the library or exports.
    func useDefaultKey(bundle: Bundle = .main) throws {
        let configured = (bundle.object(forInfoDictionaryKey: "TMDbDefaultAPIKey") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configured.isEmpty, !configured.contains("$(") else { throw DefaultKeyError() }
        try save(key: configured, proxy: nil)
    }
    private struct DefaultKeyError: LocalizedError {
        var errorDescription: String? {
            String(localized: "此构建未配置默认 API。请填写自己的 Key，或选择手动添加。")
        }
    }
    static func validatedHost(_ proxy: String?) throws -> String {
        try TMDbRequestClient.validatedHost(proxy)
    }
}

#if canImport(UIKit)
@MainActor @Observable final class TMDbEnvironment {
    static let shared = TMDbEnvironment()
    let settings = TMDbSettings()
    let images = TMDbImagePipeline()
    @ObservationIgnored lazy var service: any TMDbServing = TMDbService(connection: { [settings] in await settings.connection })
}

#endif
