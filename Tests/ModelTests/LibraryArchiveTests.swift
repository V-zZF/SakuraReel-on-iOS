import Foundation

// 导出 / 导入 / 合并 / 索引修正的断言。
// 由 main.swift 调用，断言计数与失败汇总也在那边。

// MARK: - 造数据的小工具

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

func makeItem(
    title: String,
    id: UUID = UUID(),
    year: Int? = 2024,
    month: Int? = 3,
    rating: Int = 0,
    sortIndex: Int = 0,
    rankIndex: Int? = nil,
    createdAt: Date = t0,
    updatedAt: Date = t0,
    poster: Data? = nil
) -> MediaItem {
    var item = MediaItem(
        id: id,
        title: title,
        status: .watched,
        watchYear: year,
        watchMonth: month,
        rating: rating,
        sortIndex: sortIndex,
        rankIndex: rankIndex,
        createdAt: createdAt,
        updatedAt: updatedAt
    )
    item.poster = poster
    return item
}

func makeTempFolder() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("SakuraReelModelTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func posterBytes(_ seed: UInt8) -> Data {
    Data([seed, seed, seed, seed])
}

private func title(named title: String, in items: [MediaItem]) -> MediaItem? {
    items.first { $0.title == title }
}

// MARK: - 1. 导出

func runExportTests() {
    print("\n— 导出 —")
    let folder = makeTempFolder()

    let a = makeItem(title: "千与千寻", rating: 10, poster: posterBytes(1))
    let b = makeItem(title: "沙丘2", rating: 7)   // 没有海报
    do {
        try LibraryArchive.export([a, b], to: folder)
    } catch {
        expect(false, "导出不该抛错：\(error)")
        return
    }

    let libraryURL = folder.appendingPathComponent(LibraryFiles.libraryFileName)
    expect(FileManager.default.fileExists(atPath: libraryURL.path),
           "导出后应该有 \(LibraryFiles.libraryFileName)")

    let posterURL = folder.appendingPathComponent("Posters/\(a.id.uuidString).jpg")
    expect(FileManager.default.fileExists(atPath: posterURL.path),
           "有海报的条目应该写出 <id>.jpg")
    let posterCount = (try? FileManager.default.contentsOfDirectory(
        atPath: folder.appendingPathComponent("Posters").path))?.count ?? -1
    expectEqual(posterCount, 1, "没海报的条目不该产生文件")

    // 解回来必须一致
    do {
        let readBack = try LibraryArchive.read(from: folder)
        expectEqual(readBack.count, 2, "读回的条目数")
        expectEqual(title(named: "千与千寻", in: readBack)?.rating, 10, "读回的评分")
        expectEqual(title(named: "千与千寻", in: readBack)?.poster, posterBytes(1), "读回的海报")
        expectEqual(title(named: "沙丘2", in: readBack)?.poster, nil, "没海报的条目读回来仍是 nil")
    } catch {
        expect(false, "读回不该抛错：\(error)")
    }

    // 再导出一次：换掉海报内容，旧文件必须被覆盖而不是留下两份
    var a2 = a
    a2.poster = posterBytes(9)
    try? LibraryArchive.export([a2, b], to: folder)
    let readBack = (try? LibraryArchive.read(from: folder)) ?? []
    expectEqual(title(named: "千与千寻", in: readBack)?.poster, posterBytes(9), "重复导出应覆盖海报")

    // 清理：只删本 App 命名（<UUID>.jpg）的孤儿文件
    let postersFolder = folder.appendingPathComponent("Posters")
    let orphanID = UUID()
    try? Data([7]).write(to: postersFolder.appendingPathComponent("\(orphanID.uuidString).jpg"))
    try? Data([7]).write(to: postersFolder.appendingPathComponent("我的照片.jpg"))
    try? LibraryArchive.export([b], to: folder)   // 只剩没海报的 b
    let remaining = Set((try? FileManager.default.contentsOfDirectory(atPath: postersFolder.path)) ?? [])
    expect(!remaining.contains("\(orphanID.uuidString).jpg"), "库外的 <UUID>.jpg 应被清掉")
    expect(remaining.contains("我的照片.jpg"), "不像本 App 产物的文件一律不能碰")

    try? FileManager.default.removeItem(at: folder)
}

// MARK: - 2 / 3 / 4. 合并

func runMergeTests() {
    print("\n— 合并 —")

    // 2. 导进空库：全部新增
    let folderItems = (0..<3).map { makeItem(title: "片\($0)", poster: posterBytes(UInt8($0))) }
    let empty = LibraryArchive.merge(incoming: folderItems, into: [])
    expectEqual(empty.summary.added, 3, "空库导入的新增数")
    expectEqual(empty.summary.updated, 0, "空库导入的更新数")
    expectEqual(empty.summary.kept, 0, "空库导入的保留数")
    expectEqual(empty.items.count, 3, "空库导入后的条目数")

    // 3. 有重叠的库：新增 / 更新 / 跳过 / 保留 各一
    let sharedID = UUID()
    let newerID = UUID()
    let localOnlyID = UUID()

    let local = [
        makeItem(title: "两边都有-文件更新", id: sharedID, updatedAt: t0),
        makeItem(title: "两边都有-本机更新", id: newerID, updatedAt: t0.addingTimeInterval(1000)),
        makeItem(title: "本机独有", id: localOnlyID, updatedAt: t0),
    ]
    let incoming = [
        makeItem(title: "两边都有-文件更新", id: sharedID, updatedAt: t0.addingTimeInterval(500)),
        makeItem(title: "两边都有-本机更新", id: newerID, updatedAt: t0.addingTimeInterval(600)),
        makeItem(title: "只有文件里有", updatedAt: t0),
    ]

    let result = LibraryArchive.merge(incoming: incoming, into: local)
    expectEqual(result.summary.added, 1, "新增数")
    expectEqual(result.summary.updated, 1, "更新数")
    expectEqual(result.summary.skipped, 1, "跳过数")
    expectEqual(result.summary.kept, 1, "保留数")
    expectEqual(result.items.count, 4, "合并后的条目数")
    expect(result.items.contains { $0.id == localOnlyID }, "本机独有的条目必须还在")

    // 4. 旧快照不能倒退本机数据
    let stale = [makeItem(title: "两边都有-本机更新", id: newerID,
                          updatedAt: t0.addingTimeInterval(100))]   // 比本机旧
    let staleResult = LibraryArchive.merge(incoming: stale, into: local)
    expectEqual(staleResult.summary.updated, 0, "更旧的快照不该产生更新")
    expectEqual(staleResult.summary.skipped, 1, "更旧的快照应记为跳过")
    expectEqual(title(named: "两边都有-本机更新", in: staleResult.items)?.updatedAt,
                t0.addingTimeInterval(1000), "本机较新的 updatedAt 不能被倒退")

    // 同 updatedAt 的平局必须是对称裁决：反过来合一次，赢家得是同一条
    let tie = makeItem(title: "平局-远端", id: sharedID, sortIndex: 0, updatedAt: t0)
    let tieLocal = [makeItem(title: "平局-本机", id: sharedID, sortIndex: 5, updatedAt: t0)]
    let forward = LibraryArchive.merge(incoming: [tie], into: tieLocal)
    let backward = LibraryArchive.merge(incoming: tieLocal, into: [tie])
    expectEqual(title(named: "平局-远端", in: forward.items)?.title,
                title(named: "平局-远端", in: backward.items)?.title,
                "平局裁决必须对称，否则两台设备永远合不拢")

    print("\n— 合并后的海报 —")
    // 更新时海报跟着换
    let posterID = UUID()
    let localWithPoster = [makeItem(title: "换海报", id: posterID,
                                    updatedAt: t0, poster: posterBytes(1))]
    let incomingWithPoster = [makeItem(title: "换海报", id: posterID,
                                       updatedAt: t0.addingTimeInterval(500),
                                       poster: posterBytes(2))]
    let swapped = LibraryArchive.merge(incoming: incomingWithPoster, into: localWithPoster)
    expectEqual(swapped.items.first?.poster, posterBytes(2), "更新时海报应跟着换成新版")
}

// MARK: - 5 / 6. 索引修正

func runNormalizeTests() {
    print("\n— 索引修正 —")

    // 首页：只有撞车的组被重编，别的组一个数都不许动
    let conflict = [
        makeItem(title: "撞A", year: 2024, month: 3, sortIndex: 3),
        makeItem(title: "撞B", year: 2024, month: 3, sortIndex: 3),
    ]
    let untouched = [
        makeItem(title: "没撞A", year: 2024, month: 1, sortIndex: 5),
        makeItem(title: "没撞B", year: 2024, month: 1, sortIndex: 7),
    ]
    let (fixed, fixedCount) = LibraryArchive.normalizeIndices(conflict + untouched)
    expectEqual(fixedCount, 2, "只有撞车那组的 2 条被重编")
    expectEqual(Set(fixed.filter { $0.watchMonth == 3 }.map(\.sortIndex)), Set([0, 1]),
                "撞车的组应被压成 0…n-1")
    expectEqual(title(named: "没撞A", in: fixed)?.sortIndex, 5, "没撞的组不能被动")
    expectEqual(title(named: "没撞B", in: fixed)?.sortIndex, 7, "没撞的组不能被动")

    // 下面几条评分用例都给了互不相同的 sortIndex：默认值会让同一年月组也撞车，
    // 那样 fixedCount 里就混进了首页那一维的修正数，断言就不再是「只测评分组」。

    // 排行榜：全 nil 的组是「从没手动排过」，必须保持 nil
    let allNil = [
        makeItem(title: "全nil-A", rating: 8, sortIndex: 0, rankIndex: nil),
        makeItem(title: "全nil-B", rating: 8, sortIndex: 1, rankIndex: nil),
    ]
    let (nilResult, nilFixed) = LibraryArchive.normalizeIndices(allNil)
    expectEqual(nilFixed, 0, "全 nil 的评分组不该被重编")
    expect(nilResult.allSatisfy { $0.rankIndex == nil }, "全 nil 的组重编后仍应全为 nil")

    // 排行榜：撞车 → 重编
    let dupRank = [
        makeItem(title: "撞档A", rating: 10, sortIndex: 0, rankIndex: 0),
        makeItem(title: "撞档B", rating: 10, sortIndex: 1, rankIndex: 0),
    ]
    let (dupFixed, dupCount) = LibraryArchive.normalizeIndices(dupRank)
    expectEqual(dupCount, 2, "rankIndex 撞车应被重编")
    expectEqual(Set(dupFixed.map { $0.rankIndex ?? -1 }), Set([0, 1]), "重编后应是 0…n-1")

    // 排行榜：一半 nil 一半有值 —— nil 按 0 参与比较，会和真正的 0 号静默并列
    let mixed = [
        makeItem(title: "混合-nil", rating: 6, sortIndex: 0, rankIndex: nil),
        makeItem(title: "混合-0", rating: 6, sortIndex: 1, rankIndex: 0),
    ]
    let (mixedFixed, mixedCount) = LibraryArchive.normalizeIndices(mixed)
    expectEqual(mixedCount, 2, "nil 与非 nil 混在一起也算冲突")
    expectEqual(Set(mixedFixed.map { $0.rankIndex ?? -1 }), Set([0, 1]), "混合组重编后应全部有值")

    // 两个维度同时撞车：fixedCount 数的是「修正处数」，同一条在两个维度各算一处，
    // 所以这里 2 条 × 2 维 = 4 —— 上报给用户的数字是这个语义，别被当成条目数
    let bothDimensions = [
        makeItem(title: "双撞-A", year: 2024, month: 3, rating: 10, sortIndex: 2, rankIndex: 0),
        makeItem(title: "双撞-B", year: 2024, month: 3, rating: 10, sortIndex: 2, rankIndex: 0),
    ]
    let (bothFixed, bothCount) = LibraryArchive.normalizeIndices(bothDimensions)
    expectEqual(bothCount, 4, "两个维度各撞一次应各算一处")
    expectEqual(Set(bothFixed.map(\.sortIndex)), Set([0, 1]), "首页组重编后应是 0…n-1")
    expectEqual(Set(bothFixed.map { $0.rankIndex ?? -1 }), Set([0, 1]), "评分组重编后应是 0…n-1")
}
