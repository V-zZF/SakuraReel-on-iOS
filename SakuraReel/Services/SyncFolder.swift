import Foundation

enum SyncFolderError: LocalizedError {
    /// 还没选过文件夹
    case notChosen
    /// 授权失效：文件夹被删 / 移动 / 改名，或 App 被重装
    case bookmarkInvalid

    var errorDescription: String? {
        switch self {
        case .notChosen:
            return "请先选择同步文件夹。"
        case .bookmarkInvalid:
            return "同步文件夹的授权已失效（文件夹被删除、移动或改名，或 App 被重装过），请重新选择。"
        }
    }
}

/// 用户通过系统文档选择器授权并「记住」的同步文件夹。
///
/// 这里**只用文档选择器授予的 security-scoped 访问**，不涉及 iCloud entitlement、
/// 不涉及 ubiquity container、不涉及 CloudKit —— 所以免费开发者账号也能用。
///
/// 授权以 bookmark 形式存在 `UserDefaults`（KB 级数据，且 App 一重装 bookmark 本来
/// 也就失效了，不需要 Keychain 级保护）。路径字符串**不是**数据源：解析出的 URL 与当初
/// 选的路径不保证一致（FileProvider 会重写成自己的存储路径），永远以解析结果为准。
enum SyncFolder {
    private static let bookmarkKey = "SakuraReel.syncFolderBookmark"
    private static let nameKey = "SakuraReel.syncFolderName"

    private static var defaults: UserDefaults { .standard }

    /// 已记住的文件夹名；nil = 还没选过
    static var displayName: String? { defaults.string(forKey: nameKey) }

    static var hasFolder: Bool { defaults.data(forKey: bookmarkKey) != nil }

    /// 记住用户选定的文件夹。
    ///
    /// **必须在文档选择器的回调里、该 URL 的 security scope 内调用** —— 授权只在回调
    /// 存续期间有效，离开回调之后再建 bookmark 会失败。
    static func remember(_ folder: URL) {
        guard let data = try? folder.bookmarkData() else { return }
        defaults.set(data, forKey: bookmarkKey)
        defaults.set(folder.lastPathComponent, forKey: nameKey)
    }

    static func forget() {
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: nameKey)
    }

    /// 打开授权 → 执行 `body` → 关闭。**所有**对同步文件夹的读写都必须走这里。
    ///
    /// `start` 返回 false 不代表失败：不是 security-scoped 的 URL（例如本机沙盒内的路径）
    /// 本来就会返回 false。那种情况下照常执行，也不要 `stop` —— 授权是进程级引用计数的，
    /// 乱配对会漏掉一次 stop。
    ///
    /// 授权可以跨越 `await` 一直持有，所以调用方完全可以把真正的读写拆到 detached task 里
    /// 去跑 —— 这正是必须的：云盘上的文件可能要先下载，那段等待不能占着主线程。
    static func withAccess<T: Sendable>(_ body: @Sendable (URL) async throws -> T) async throws -> T {
        let folder = try resolve()
        let didStart = folder.startAccessingSecurityScopedResource()
        defer { if didStart { folder.stopAccessingSecurityScopedResource() } }
        return try await body(folder)
    }

    private static func resolve() throws -> URL {
        guard let data = defaults.data(forKey: bookmarkKey) else { throw SyncFolderError.notChosen }

        var isStale = false
        let folder: URL
        do {
            folder = try URL(
                resolvingBookmarkData: data,
                options: .withoutUI,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            // 解析不出来说明授权已经没救了，清掉让用户重选，免得每次操作都报同一个错
            forget()
            throw SyncFolderError.bookmarkInvalid
        }

        if isStale, let refreshed = try? folder.bookmarkData() {
            defaults.set(refreshed, forKey: bookmarkKey)
        }
        // 顺手刷新名字：解析出的路径可能与当初选的不同
        defaults.set(folder.lastPathComponent, forKey: nameKey)

        guard FileManager.default.fileExists(atPath: folder.path) else {
            // 不 forget()：可能只是云盘暂时没挂上。让用户自己决定要不要重选。
            throw SyncFolderError.bookmarkInvalid
        }
        return folder
    }
}
