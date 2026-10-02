import Foundation

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

func makeItem(title: String, id: UUID = UUID(), year: Int? = 2024, month: Int? = 3,
              rating: Int = 0, sortIndex: Int = 0, rankIndex: Int? = nil,
              updatedAt: Date = t0, poster: Data? = nil) -> MediaItem {
    MediaItem(id: id, title: title, poster: poster, status: .watched, watchYear: year,
              watchMonth: month, rating: rating, sortIndex: sortIndex, rankIndex: rankIndex,
              createdAt: t0, updatedAt: updatedAt)
}

private func temporaryFolder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func runArchiveTests() {
    print("\n— 整库快照与覆盖 —")
    let a = makeItem(title: "A", rating: 10, sortIndex: 0, rankIndex: 0, poster: Data([1]))
    let b = makeItem(title: "B", rating: 10, sortIndex: 1, rankIndex: 1)
    let source = LibrarySnapshot(items: [a, b], homeOrder: [b.id, a.id], rankingOrder: [a.id, b.id])
    let folder = temporaryFolder()
    do {
        try LibraryArchive.export(source, to: folder)
        let read = try LibraryArchive.read(from: folder)
        expectEqual(read.homeOrder, [b.id, a.id], "首页顺序完整往返")
        expectEqual(read.rankingOrder, [a.id, b.id], "排行榜顺序完整往返")
        expectEqual(read.items.first?.poster, Data([1]), "海报往返")
        expectEqual(MediaSort.homeSorted(read.items, order: read.homeOrder).map(\.id), [b.id, a.id], "首页采用独立顺序")
        expectEqual(MediaSort.rankingSorted(read.items, order: read.rankingOrder).map(\.id), [a.id, b.id], "排行榜采用独立顺序")

        let localOnly = makeItem(title: "本机独有", poster: Data([9]))
        let newerLocal = makeItem(title: "本机较新", id: a.id, updatedAt: t0.addingTimeInterval(1000))
        let local = LibrarySnapshot(items: [newerLocal, localOnly], homeOrder: [newerLocal.id, localOnly.id], rankingOrder: [localOnly.id, newerLocal.id])
        let summary = LibraryArchive.summary(incoming: read, local: local)
        expectEqual(summary.deletedCount, 1, "本机独有条目计入删除")
        expectEqual(read.items.first?.title, "A", "旧云端内容覆盖较新本机编辑")
        expectEqual(read.items.count, 2, "导入内容就是云端快照")

        let changed = LibrarySnapshot(items: [a, b], homeOrder: [a.id, b.id], rankingOrder: [b.id, a.id])
        try LibraryArchive.export(changed, to: folder)
        let reread = try LibraryArchive.read(from: folder)
        expectEqual(reread.homeOrder, [a.id, b.id], "仅调整旧作品首页位置可传播")
        expectEqual(reread.rankingOrder, [b.id, a.id], "仅调整旧作品排行榜位置可传播")

        let empty = LibrarySnapshot(items: [], homeOrder: [], rankingOrder: [])
        try LibraryArchive.export(empty, to: folder)
        expectEqual(try LibraryArchive.read(from: folder).items.count, 0, "空云端库可覆盖本机")
        let posterURL = folder.appendingPathComponent("Posters/\(a.id.uuidString).jpg")
        expect(!FileManager.default.fileExists(atPath: posterURL.path), "云端导出删除已不存在的海报")
    } catch {
        expect(false, "快照导出导入失败：\(error)")
    }
    try? FileManager.default.removeItem(at: folder)
}

func runLegacyTests() {
    print("\n— 旧版迁移与顺序维护 —")
    let a = makeItem(title: "A", sortIndex: 1, rankIndex: 1)
    let b = makeItem(title: "B", sortIndex: 0, rankIndex: 0)
    do {
        let oldJSON = try LibraryCoding.encoder.encode([a, b])
        let migrated = try LibrarySnapshot.decode(oldJSON)
        expectEqual(migrated.homeOrder, [b.id, a.id], "旧版首页索引迁移")
        expectEqual(migrated.rankingOrder, [b.id, a.id], "旧版排行榜索引迁移")
        let newJSON = try migrated.encoded()
        let restored = try LibrarySnapshot.decode(newJSON)
        expectEqual(restored.homeOrder, migrated.homeOrder, "新格式重启保留首页顺序")
        expectEqual(restored.rankingOrder, migrated.rankingOrder, "新格式重启保留排行榜顺序")
    } catch {
        expect(false, "旧版迁移失败：\(error)")
    }
    let otherMonth = makeItem(title: "旧月份", month: 2)
    let cross = LibrarySnapshot(items: [a, b, otherMonth], homeOrder: [otherMonth.id, a.id, b.id], rankingOrder: [a.id, b.id, otherMonth.id])
    expectEqual(MediaSort.homeSorted(cross.items, order: cross.homeOrder).map(\.id), [a.id, b.id, otherMonth.id], "顺序表不能跨年月改变分组")
    let higherA = makeItem(title: "高分A", id: a.id, rating: 10)
    let higherB = makeItem(title: "高分B", id: b.id, rating: 10)
    let lowerRating = makeItem(title: "低分", rating: 2)
    let rating = LibrarySnapshot(items: [higherA, higherB, lowerRating], homeOrder: [a.id, b.id, lowerRating.id], rankingOrder: [lowerRating.id, a.id, b.id])
    expectEqual(MediaSort.rankingSorted(rating.items, order: rating.rankingOrder).map(\.id), [a.id, b.id, lowerRating.id], "顺序表不能跨评分改变分组")
    let added = makeItem(title: "新增")
    let repaired = LibrarySnapshot(items: [a, b, added], homeOrder: [b.id, a.id], rankingOrder: [b.id, a.id])
    expectEqual(Set(repaired.homeOrder), Set([a.id, b.id, added.id]), "新增条目加入首页顺序")
    expectEqual(Set(repaired.rankingOrder), Set([a.id, b.id, added.id]), "新增条目加入排行榜顺序")
    let moved = makeItem(title: "移组", id: a.id, year: 2025, month: 1, rating: 9)
    let afterEdit = LibrarySnapshot(items: [moved, b], homeOrder: [b.id], rankingOrder: [b.id])
    expectEqual(afterEdit.homeOrder, [b.id, a.id], "编辑换年月时从旧顺序移除并加入新组")
    expectEqual(afterEdit.rankingOrder, [b.id, a.id], "编辑换评分时从旧顺序移除并加入新组")
    let afterDelete = LibrarySnapshot(items: [b], homeOrder: [a.id, b.id], rankingOrder: [a.id, b.id])
    expectEqual(afterDelete.homeOrder, [b.id], "删除条目从首页顺序移除")
    expectEqual(afterDelete.rankingOrder, [b.id], "删除条目从排行榜顺序移除")
}
