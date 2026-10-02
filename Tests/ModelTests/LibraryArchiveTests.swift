import Foundation

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
func makeItem(title: String, id: UUID = UUID(), year: Int? = 2024, month: Int? = 3,
              rating: Int = 0, updatedAt: Date = t0, poster: Data? = nil) -> MediaItem {
    MediaItem(id: id, title: title, poster: poster, status: .watched, watchedAt: year.flatMap { year in month.map { YearMonth(year: year, month: $0) } }, rating: rating, createdAt: t0, updatedAt: updatedAt)
}
private func rejected(_ message: String, _ operation: () throws -> Void) {
    do { try operation(); expect(false, message) } catch { expect(true, message) }
}
private func temporaryFolder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
func runDocumentTests() {
    print("\n— 版本、校验与分组排序 —")
    let a = makeItem(title: "A", rating: 10)
    let b = makeItem(title: "B", rating: 10)
    let older = makeItem(title: "旧月", month: 2, rating: 9)
    var shifted = [a, b, makeItem(title: "C", rating: 10), older]
    let c = shifted[2]
    MediaSort.moveWithinGroup(&shifted, from: 0, to: 2, ranking: false)
    expectEqual(shifted.map(\.id), [b.id, c.id, a.id, older.id], "向后移动由后方邻卡依次补位")
    MediaSort.moveWithinGroup(&shifted, from: 2, to: 0, ranking: false)
    expectEqual(shifted.map(\.id), [a.id, b.id, c.id, older.id], "向前移动由前方邻卡依次补位")
    MediaSort.moveWithinGroup(&shifted, from: 0, to: 3, ranking: false)
    expectEqual(shifted.map(\.id), [a.id, b.id, c.id, older.id], "即时拖动拒绝跨年月")
    MediaSort.moveWithinGroup(&shifted, from: 0, to: 2, ranking: true)
    expectEqual(shifted.map(\.id), [b.id, c.id, a.id, older.id], "排行榜同评分顺位补位")
    MediaSort.moveWithinGroup(&shifted, from: 0, to: 3, ranking: true)
    expectEqual(shifted.map(\.id), [b.id, c.id, a.id, older.id], "即时拖动拒绝跨评分")
    do {
        var additions = LibraryDocument(items: [a, b, older])
        try additions.upsert(c)
        expectEqual(additions.homeOrder, [c.id, a.id, b.id, older.id], "新添加作品置于对应年月组首位")
        try additions.upsert(c)
        expectEqual(additions.homeOrder, [c.id, a.id, b.id, older.id], "编辑保留组内位置")
        expectEqual(try LibraryDocument.decode(additions.encoded()).homeOrder, additions.homeOrder, "新添加顺序持久化")
    } catch { expect(false, "新添加排序失败：\(error)") }
    do {
        var watchingA = makeItem(title: "在看A", rating: 10); watchingA.status = .watching
        var watchingB = makeItem(title: "在看B", rating: 10); watchingB.status = .watching
        var wantedA = makeItem(title: "想看A", rating: 10); wantedA.status = .wantToWatch
        var wantedB = makeItem(title: "想看B", rating: 10); wantedB.status = .wantToWatch
        var categories = LibraryDocument(items: [a, watchingA, wantedA, b, watchingB, wantedB, older])
        func categoryOrder(_ status: MediaStatus) -> [UUID] { categories.homeItems.filter { $0.status == status }.map(\.id) }
        expectEqual(categories.rankingOrder, [a.id, b.id, older.id], "排行榜仅包含看过")
        try categories.reorderHome([b.id, a.id, older.id], status: .watched)
        expectEqual(categoryOrder(.watching), [watchingA.id, watchingB.id], "排序看过不影响在看")
        expectEqual(categoryOrder(.wantToWatch), [wantedA.id, wantedB.id], "排序看过不影响想看")
        try categories.reorderHome([watchingB.id, watchingA.id], status: .watching)
        try categories.reorderHome([wantedB.id, wantedA.id], status: .wantToWatch)
        expectEqual(categoryOrder(.watched), [b.id, a.id, older.id], "排序另外两类保留看过顺序")
        expectEqual(categoryOrder(.watching), [watchingB.id, watchingA.id], "在看独立排序")
        expectEqual(categoryOrder(.wantToWatch), [wantedB.id, wantedA.id], "想看独立排序")
        rejected("分类排序拒绝混入其他状态") { try categories.reorderHome([a.id, watchingA.id], status: .watching) }
        rejected("分类排序拒绝跨年月") { try categories.reorderHome([older.id, a.id, b.id], status: .watched) }
        try categories.reorder([a.id, b.id, older.id], ranking: true)
        expectEqual(categories.rankingOrder, [a.id, b.id, older.id], "排行榜排序只提交看过")
        expectEqual(categoryOrder(.watching), [watchingB.id, watchingA.id], "排行榜排序保留在看首页顺序")
        rejected("排行榜拒绝在看条目") { try categories.reorder([a.id, watchingA.id, older.id], ranking: true) }
        var changed = a; changed.status = .watching
        try categories.upsert(changed)
        expectEqual(categories.rankingOrder, [b.id, older.id], "看过改为在看即时退出排行榜")
        changed.status = .watched
        try categories.upsert(changed)
        expectEqual(categories.rankingOrder, [a.id, b.id, older.id], "改回看过恢复历史排行榜位置")
        let decoded = try LibraryDocument.decode(categories.encoded())
        expectEqual(decoded.homeOrder, categories.homeOrder, "三个分类独立顺序持久化")
        expectEqual(decoded.rankingOrder, categories.rankingOrder, "排行榜过滤与顺序持久化")
        let empty = LibraryDocument(items: [watchingA, wantedA])
        expect(empty.rankedItems.isEmpty, "仅在看想看时排行榜为空")
    } catch { expect(false, "分类独立排序失败：\(error)") }
    var document = LibraryDocument(items: [a, b, older])
    do {
        let restored = try LibraryDocument.decode(document.encoded())
        expectEqual(restored.libraryID, document.libraryID, "资料库身份往返")
        expectEqual(restored.homeOrder, [a.id, b.id, older.id], "首页默认组内添加顺序")
        expectEqual(restored.rankingOrder, [a.id, b.id, older.id], "排行榜默认沿用年月与首页组内顺序")
        expect(restored.rankingGroups.isEmpty, "未拖动不存评分组顺序")
        try document.reorder([b.id, a.id, older.id], ranking: false)
        expectEqual(document.rankingOrder, [b.id, a.id, older.id], "未手动评分组跟随首页组内顺序")
        try document.reorder([a.id, b.id, older.id], ranking: true)
        expectEqual(document.rankingGroups.count, 1, "只保存发生手动排序的评分组")
        try document.reorder([a.id, b.id, older.id], ranking: false)
        expectEqual(document.rankingOrder, [a.id, b.id, older.id], "手动排行榜独立于首页")
        rejected("拒绝跨年月拖动") { try document.reorder([older.id, a.id, b.id], ranking: false) }
        rejected("拒绝跨评分拖动") { try document.reorder([older.id, a.id, b.id], ranking: true) }
        rejected("拒绝排序遗漏") { try document.reorder([a.id], ranking: false) }
        var moved = a; moved.personal.watchedAt = YearMonth(year: 2024, month: 2)
        try document.upsert(moved, now: t0.addingTimeInterval(20))
        expectEqual(document.homeGroups.first { $0.month?.month == 2 }?.ids, [older.id, a.id], "换年月追加至目标组末尾")
        expectEqual(document.rankingOrder, [a.id, b.id, older.id], "换年月保留同评分手动位置")
        var newEntry = makeItem(title: "新", rating: 10)
        try document.upsert(newEntry, now: t0.addingTimeInterval(30))
        expectEqual(document.rankingOrder, [newEntry.id, a.id, b.id, older.id], "新条目按默认规则插入手动组，已有相对顺序保持")
        newEntry.rating = 9
        try document.upsert(newEntry, now: t0.addingTimeInterval(40))
        expectEqual(document.rankingGroups.first?.ids, [a.id, b.id], "换评分从原手动组移除")
        try document.remove(a.id)
        expect(!document.homeOrder.contains(a.id) && !document.rankingOrder.contains(a.id), "删除移除两种顺序引用")
        try LibraryValidator.validate(document)
    } catch { expect(false, "分组操作失败：\(error)") }

    func invalid(_ label: String, _ mutate: (inout LibraryDocument) -> Void) {
        var candidate = LibraryDocument(items: [a, b]); mutate(&candidate)
        rejected(label) { try LibraryValidator.validate(candidate) }
    }
    invalid("拒绝重复 UUID") { $0.items[1].id = a.id }
    invalid("拒绝评分越界") { $0.items[0].rating = 11 }
    invalid("拒绝非法月份") { $0.items[0].personal.watchedAt?.month = 13 }
    invalid("拒绝非法年份") { $0.items[0].personal.watchedAt?.year = 0 }
    invalid("拒绝缺失首页引用") { $0.homeGroups[0].ids.removeLast() }
    invalid("拒绝未知首页引用") { $0.homeGroups[0].ids[0] = UUID() }
    invalid("拒绝重复年月组") { $0.homeGroups.append($0.homeGroups[0]) }
    invalid("拒绝不完整手动评分组") { $0.rankingGroups = [RankingOrderGroup(rating: 10, ids: [a.id])] }
    invalid("拒绝重复手动组条目") { $0.rankingGroups = [RankingOrderGroup(rating: 10, ids: [a.id, a.id])] }
    invalid("拒绝跨评分引用") { $0.rankingGroups = [RankingOrderGroup(rating: 9, ids: [a.id, b.id])] }
    invalid("拒绝非法附件格式") { $0.items[0].attachments.logo = "jpg" }
    invalid("拒绝重复 TMDb 身份") {
        let source = MediaSource(tmdb: .movie(id: 1), language: "zh-CN", fetchedAt: t0)
        $0.items[0].source = source; $0.items[1].source = source
    }
    invalid("拒绝不完整季度") { $0.items[0].source = MediaSource(tmdb: .season(id: 1, seriesID: 0, number: -1), language: "zh-CN", fetchedAt: t0) }
    do {
        var future = LibraryDocument(items: [a]); future.schemaVersion = 2
        rejected("拒绝未知格式版本") { _ = try LibraryDocument.decode(LibraryCoding.encoder.encode(future)) }
        rejected("拒绝旧数组格式") { _ = try LibraryDocument.decode(LibraryCoding.encoder.encode([a])) }
        rejected("拒绝旧快照格式") { _ = try LibraryDocument.decode(Data("{\"items\":[],\"homeOrder\":[],\"rankingOrder\":[]}".utf8)) }
        var distinct = LibraryDocument(items: [a, b])
        distinct.items[0].source = MediaSource(tmdb: .movie(id: 7), language: "zh-CN", fetchedAt: t0)
        distinct.items[1].source = MediaSource(tmdb: .series(id: 7), language: "zh-CN", fetchedAt: t0)
        try LibraryValidator.validate(distinct)
        expect(true, "相同数字的电影和剧集身份不同")
    } catch { expect(false, "身份测试失败：\(error)") }
}
func runArchiveTests() {
    print("\n— 文件事务与完整备份 —")
    var a = makeItem(title: "A", rating: 10, poster: Data([1]))
    a.backdrop = Data([2]); a.logo = Data([3])
    let b = makeItem(title: "B", rating: 10)
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    do {
        var source = LibraryDocument(items: [a, b])
        try source.reorder([b.id, a.id], ranking: false)
        try LibraryArchive.export(source, to: folder)
        let read = try LibraryArchive.read(from: folder)
        expectEqual(read.items, source.items, "资料与三种附件完整往返")
        expectEqual(read.homeOrder, [b.id, a.id], "首页组内顺序往返")
        let light = try LibraryArchive.read(from: folder, hydrate: false)
        expect(light.items[0].poster == nil && light.items[0].attachments.poster == "jpg", "列表读入描述，不读图片字节")
        try LibraryArchive.commit(light, to: folder)
        expectEqual(try LibraryArchive.read(from: folder).items[0].logo, Data([3]), "轻量保存保留既有附件")
        let backup = temporaryFolder(); defer { try? FileManager.default.removeItem(at: backup) }
        try LibraryArchive.export(read, to: backup)
        expectEqual(try LibraryArchive.read(from: backup).items, source.items, "完整备份往返")

        let rollback = folder.appendingPathComponent(".rollback-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: rollback, withIntermediateDirectories: true)
        let names = [LibraryFiles.libraryFileName, LibraryFiles.postersDirectoryName, LibraryFiles.artworkDirectoryName]
        for name in names { try FileManager.default.copyItem(at: folder.appendingPathComponent(name), to: rollback.appendingPathComponent(name)) }
        try JSONEncoder().encode(names).write(to: rollback.appendingPathComponent("originals.json"))
        try Data("broken".utf8).write(to: folder.appendingPathComponent(LibraryFiles.libraryFileName))
        try FileManager.default.removeItem(at: folder.appendingPathComponent("Artwork"))
        expectEqual(try LibraryArchive.read(from: folder).items, source.items, "中断提交恢复 JSON 与全部图片")
        expect(!FileManager.default.fileExists(atPath: rollback.path), "恢复成功移除回滚目录")

        let poster = folder.appendingPathComponent(AttachmentKind.poster.path(for: a.id))
        try FileManager.default.removeItem(at: poster)
        let missing = try LibraryArchive.read(from: folder)
        expect(!missing.warnings.isEmpty && missing.items[0].attachments.poster == "jpg", "缺失附件报告且保留描述")
        try LibraryArchive.commit(missing, to: folder)
        expectEqual(try LibraryArchive.read(from: folder).items[0].attachments.poster, "jpg", "缺失附件描述不会被保存删除")
        try FileManager.default.createDirectory(at: poster, withIntermediateDirectories: true)
        rejected("已有但不可读的附件使提交失败") { try LibraryArchive.commit(light, to: folder) }
        let preserved = try LibraryDocument.decode(Data(contentsOf: folder.appendingPathComponent(LibraryFiles.libraryFileName)))
        expectEqual(preserved.homeOrder, light.homeOrder, "附件读取失败保持原 JSON")
        try FileManager.default.removeItem(at: poster)
        try LibraryArchive.commit(LibraryDocument(), to: folder)
        expectEqual(try LibraryArchive.read(from: folder).items.count, 0, "整库替换允许空库")
        expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(AttachmentKind.logo.path(for: a.id)).path), "整库替换清理不再引用的附件")
    } catch { expect(false, "文件测试失败：\(error)") }
}
