import Foundation

func runTMDbMetadataTests() {
    print("\n— TMDb 草稿与本地记录分离 —")
    var original = makeItem(title: "用户片名", year: 2020, month: 2, rating: 9, poster: Data([1]))
    original.review = "我的短评"; original.playURL = "myplayer://watch"
    let source = MediaSource(tmdb: .movie(id: 10), language: "zh-CN", fetchedAt: Date(timeIntervalSince1970: 1000))
    let metadata = MediaMetadata(originalTitle: "Original", overview: "远端简介", releaseDate: "2000-01-02", genres: ["剧情"], tmdbRating: 7.5)
    let draft = TMDbImportDraft(source: source, title: "TMDb 片名", metadata: metadata, poster: Data([2]), backdrop: Data([3]), logo: Data([4]))
    let merged = draft.merging(into: original, fields: Set(MetadataField.allCases))
    expectEqual(merged.personal, original.personal, "资料提交不改变全部个人记录")
    expectEqual(merged.id, original.id, "资料提交保持本地 ID")
    let defaults = draft.defaults(for: original)
    expect(!defaults.contains(.title) && !defaults.contains(.poster), "已有片名和海报默认不替换")
    expect(defaults.contains(.overview), "空资料默认填入")
    var changed = merged; changed.metadata?.overview = "用户修改"
    expectEqual(draft.merging(into: changed, fields: draft.defaults(for: changed)).metadata?.overview, "用户修改", "重新获取默认保留用户修改")
    var translated = source; translated.language = "en-US"; translated.fetchedAt = Date()
    expectEqual(translated.tmdb, source.tmdb, "语言和获取时间不属于来源身份")
    let season = TMDbIdentity.season(id: 1, seriesID: 12, number: 1)
    expect(season != .season(id: 1, seriesID: 12, number: 2), "季号参与身份")
    expect(season != .season(id: 1, seriesID: 13, number: 1), "父剧集参与身份")
    let duration = MediaMetadata(runtimeMinutes: 25, episodeCount: 12)
    expectEqual(duration.totalRuntimeMinutes(for: .season)?.minutes, 300, "季度总时长按平均单集时长乘集数")
    expect(duration.totalRuntimeMinutes(for: .series)?.isEstimated == true, "剧集总时长明确为估算")
    expectEqual(duration.totalRuntimeMinutes(for: .movie)?.minutes, 25, "电影时长不乘集数")
    expect(duration.totalRuntimeMinutes(for: .movie)?.isEstimated == false, "电影时长不标估算")
    expect(MediaMetadata(runtimeMinutes: 25).totalRuntimeMinutes(for: .series) == nil, "剧集缺集数不伪造总时长")
    expect(MediaMetadata(episodeCount: 12).totalRuntimeMinutes(for: .season) == nil, "缺单集时长不伪造总时长")
    expect(MediaMetadata(runtimeMinutes: Int.max, episodeCount: 2).totalRuntimeMinutes(for: .series) == nil, "时长乘法溢出不崩溃")
    expectEqual(duration.totalRuntimeMinutes(for: nil)?.minutes, 300, "无来源且有集数的本地资料按剧集估算")
    do {
        var document = LibraryDocument(items: [original, makeItem(title: "另一部", year: 2020, month: 2, rating: 9)])
        try document.reorder(document.rankingOrder.reversed(), ranking: true)
        let home = document.homeOrder; let ranking = document.rankingOrder
        try document.upsert(merged)
        expectEqual(document.homeOrder, home, "TMDb 提交不改变首页顺序")
        expectEqual(document.rankingOrder, ranking, "TMDb 提交不改变手动排行榜顺序")
        let json = try JSONSerialization.jsonObject(with: document.encoded()) as! [String: Any]
        let item = (json["items"] as! [[String: Any]])[0]
        expect(item["poster"] == nil && item["backdrop"] == nil && item["logo"] == nil, "图片字节不写 JSON")
        expect(item["sortIndex"] == nil && item["rankIndex"] == nil, "旧索引不写 JSON")
        expect(item["work"] != nil && item["personal"] != nil && item["attachments"] != nil, "结构按职责拆分")
    } catch { expect(false, "TMDb 草稿测试失败：\(error)") }
}
