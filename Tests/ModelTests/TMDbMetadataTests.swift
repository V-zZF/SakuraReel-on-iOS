import Foundation

func runTMDbMetadataTests() {
    print("\n— TMDb 本地资料与附件 —")
    var original = makeItem(title: "用户片名", year: 2020, month: 2, rating: 9, sortIndex: 7, rankIndex: 3, poster: Data([1]))
    original.review = "我的短评"; original.playURL = "myplayer://watch"
    let source = MediaSource(mediaType: .movie, remoteID: 10, language: "zh-CN", fetchedAt: Date(timeIntervalSince1970: 1000))
    let metadata = MediaMetadata(localizedTitle: "TMDb 片名", originalTitle: "Original", overview: "远端简介",
        releaseDate: "2000-01-02", genres: ["剧情"], tmdbRating: 7.5, homepage: "https://example.com",
        cast: [MediaCredit(id: "1", name: "演员", role: "角色")], seasons: [MediaPart(id: 1, number: 1, title: "季度")])
    let draft = TMDbImportDraft(source: source, title: "TMDb 片名", metadata: metadata,
                               poster: Data([2]), backdrop: Data([3]), logo: Data([4]))
    let merged = draft.merging(into: original, fields: Set(MetadataField.allCases))
    expectEqual(merged.rating, 9, "TMDb 不覆盖个人评分")
    expectEqual(merged.review, original.review, "TMDb 不覆盖短评")
    expectEqual(merged.playURL, original.playURL, "官网不填入播放链接")
    expectEqual(merged.watchYear, original.watchYear, "上映日期不覆盖观看年份")
    expectEqual(merged.watchMonth, original.watchMonth, "上映日期不覆盖观看月份")
    expectEqual(merged.status, original.status, "不覆盖观看状态")
    expectEqual(merged.id, original.id, "本地 UUID 保持不变")
    expectEqual(merged.sortIndex, original.sortIndex, "首页索引保留")
    expectEqual(merged.rankIndex, original.rankIndex, "排行榜索引保留")
    let defaults = draft.defaults(for: original)
    expect(!defaults.contains(.title) && !defaults.contains(.poster), "已有片名和海报默认不替换")
    expect(defaults.contains(.overview), "空作品资料默认填入")
    let conservative = draft.merging(into: original, fields: defaults)
    expectEqual(conservative.title, original.title, "默认保留用户片名")
    expectEqual(conservative.poster, original.poster, "默认保留用户海报")
    var changed = merged; changed.metadata?.overview = "用户自行修改"
    expectEqual(draft.merging(into: changed, fields: draft.defaults(for: changed)).metadata?.overview, "用户自行修改", "再次获取默认保留本地修改")
    var translated = source; translated.language = "en-US"; translated.fetchedAt = Date()
    expectEqual(translated.identity, source.identity, "语言与时间不改变身份")
    var series = source; series.mediaType = .series
    expect(series.identity != source.identity, "同 ID 电影剧集不同身份")
    var season = source; season.mediaType = .season; season.parentSeriesID = 12; season.seasonNumber = 1
    var other = season; other.seasonNumber = 2
    expect(other.identity != season.identity, "季度季号参与身份")
    other = season; other.parentSeriesID = 13
    expect(other.identity != season.identity, "季度父剧集参与身份")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
        let snapshot = LibrarySnapshot(items: [merged], homeOrder: [merged.id], rankingOrder: [merged.id])
        try LibraryArchive.commit(snapshot, to: directory)
        let restored = try LibraryArchive.read(from: directory)
        expectEqual(restored.items.first, merged, "完整资料及三种图片往返")
        expectEqual(restored.homeOrder, snapshot.homeOrder, "资料往返保留首页顺序")
        expectEqual(restored.rankingOrder, snapshot.rankingOrder, "资料往返保留排行榜顺序")
        let encoded = try snapshot.encoded()
        let json = String(data: encoded, encoding: .utf8)!
        expect(!json.contains("backdrop\"") && !json.contains("logo\"") && !json.contains("poster\""), "图片字节不写 JSON")
        var legacy = try JSONSerialization.jsonObject(with: LibraryCoding.encoder.encode([original])) as! [[String: Any]]
        legacy[0].removeValue(forKey: "source"); legacy[0].removeValue(forKey: "metadata")
        let old = try LibrarySnapshot.decode(JSONSerialization.data(withJSONObject: legacy))
        expect(old.items[0].source == nil && old.items[0].metadata == nil, "旧数组无新字段可读取")
        // Simulate process termination after attachment installation but before JSON commits.
        let rollback = directory.appendingPathComponent(".rollback-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: rollback, withIntermediateDirectories: true)
        let names = [LibraryFiles.libraryFileName, LibraryFiles.postersDirectoryName, LibraryFiles.artworkDirectoryName]
        for name in names { try FileManager.default.copyItem(at: directory.appendingPathComponent(name), to: rollback.appendingPathComponent(name)) }
        try JSONEncoder().encode(names).write(to: rollback.appendingPathComponent("originals.json"))
        try Data("broken".utf8).write(to: directory.appendingPathComponent(LibraryFiles.libraryFileName))
        try FileManager.default.removeItem(at: directory.appendingPathComponent(LibraryFiles.artworkDirectoryName))
        let recovered = try LibraryArchive.read(from: directory)
        expectEqual(recovered.items.first, merged, "中断保存恢复 JSON 与全部附件")
        expect(!FileManager.default.fileExists(atPath: rollback.path), "恢复完成才删除回滚文件")
        try LibraryArchive.commit(LibrarySnapshot(items: [original], homeOrder: [original.id], rankingOrder: [original.id]), to: directory)
        let cleared = try LibraryArchive.read(from: directory)
        expect(cleared.items[0].backdrop == nil && cleared.items[0].logo == nil, "覆盖导入清理旧附件")
        expectEqual(cleared.items[0].poster, original.poster, "保留海报格式")
    } catch { expect(false, "资料测试失败：\(error)") }
}
