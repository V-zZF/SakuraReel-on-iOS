import Foundation

func runSyncTests() {
    print("\n— 双向增量同步、收敛与中断恢复 —")
    let manager = FileManager.default
    var folders: [URL] = []
    func folder() throws -> URL {
        let url = manager.temporaryDirectory.appendingPathComponent("sync-tests-" + UUID().uuidString)
        try manager.createDirectory(at: url, withIntermediateDirectories: true); folders.append(url); return url
    }
    defer {
        for a in folders { for b in folders { try? manager.removeItem(at: LibrarySyncCoordinator.bookkeeping(local: a, remote: b)) } }
        for url in folders { try? manager.removeItem(at: url) }
    }
    func sync(_ a: URL, _ b: URL, choices: [String: Bool] = [:]) throws -> LibrarySyncReport {
        try LibrarySyncCoordinator.apply(LibrarySyncCoordinator.prepare(local: a, remote: b), choices: choices).1
    }
    func edit(_ folder: URL, id: UUID, _ change: (inout MediaItem) -> Void) throws {
        var doc = try LibraryArchive.read(from: folder, hydrate: false)
        var item = doc.items.first { $0.id == id }!
        change(&item); try doc.upsert(item); doc.revision += 1
        try LibraryArchive.commit(doc, to: folder)
    }
    func remove(_ folder: URL, id: UUID) throws {
        var doc = try LibraryArchive.read(from: folder, hydrate: false); try doc.remove(id); doc.revision += 1
        try LibraryArchive.commit(doc, to: folder)
    }
    func rejects(_ label: String, _ body: () throws -> Void) {
        do { try body(); expect(false, label) } catch { expect(true, label) }
    }
    do {
        let a = try folder(), b = try folder()
        var item = makeItem(title: "共同作品", rating: 7, poster: Data([1, 2, 3]))
        item.backdrop = Data([4, 5]); item.logo = Data([6])
        try LibraryArchive.commit(LibraryDocument(items: [item]), to: a)
        let first = try sync(a, b)
        expectEqual(first.added, 1, "上传本机新增条目也计入变化统计")
        expectEqual(first.transferred, 3, "首次只向空目标传输三种附件")
        expectEqual(first.readBytes, 6, "首次指纹已记录，每个源图片只读取一次")
        let before = try LibrarySyncDisk.version(in: a)
        let path = a.appendingPathComponent(AttachmentKind.poster.path(for: item.id))
        let originalDate = try path.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let idle = try sync(a, b)
        expect(idle.unchanged && idle.transferred == 0 && idle.readBytes == 0 && idle.writtenBytes == 0, "无变化同步零图片读写")
        expectEqual(try LibrarySyncDisk.version(in: a), before, "无变化不重写元数据")
        expectEqual(try path.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, originalDate, "未变图片保持文件修改时间")

        let clockBefore = try LibrarySyncDisk.read(from: a).state.records[item.id.uuidString]!.fields
        try edit(a, id: item.id) { $0.rating = 9 }
        let changedClock = try LibrarySyncDisk.read(from: a).state.records[item.id.uuidString]!.fields
        expect(changedClock["personal.rating"]! > clockBefore["personal.rating"]!, "评分变更更新独立时钟")
        expectEqual(changedClock["personal.review"], clockBefore["personal.review"], "评分变更不更新短评时钟")
        try edit(b, id: item.id) { $0.review = "另一台设备写的短评" }
        let texts = try sync(a, b)
        let merged = try LibraryArchive.read(from: a)
        expectEqual(merged.items[0].rating, 9, "保留本机评分变更")
        expectEqual(merged.items[0].review, "另一台设备写的短评", "保留远端独立短评变更")
        expect(texts.readBytes == 0 && texts.transferred == 0, "不同文字字段合并零图片传输")
        expectEqual(try LibraryArchive.read(from: b).entries, merged.entries, "两端字段合并结果一致")
        try edit(a, id: item.id) { $0.review = "先改" }
        try edit(b, id: item.id) { $0.review = "后改" }
        _ = try sync(a, b)
        expectEqual(try LibraryArchive.read(from: a).items[0].review, "后改", "同字段最后修改优先")

        try edit(b, id: item.id) { $0.poster = Data([9, 8, 7, 6]) }
        let image = try sync(a, b)
        expectEqual(image.transferred, 1, "更换海报仅更新一个文件")
        expectEqual(image.readBytes, 7, "仅读取变化海报与其原文件回滚备份")
        expectEqual(image.writtenBytes, 7, "仅写入变化海报与其回滚备份")
        expectEqual(try LibraryArchive.read(from: a).items[0].poster, Data([9, 8, 7, 6]), "变化海报同步到另一端")

    } catch { expect(false, "增量同步失败：\(error)") }
    do {
        let a = try folder(), b = try folder(), c = try folder()
        let item = makeItem(title: "删除测试", poster: Data([1]))
        try LibraryArchive.commit(LibraryDocument(items: [item]), to: a)
        _ = try sync(a, b)
        try LibraryArchive.commit(LibraryDocument(), to: c); _ = try sync(c, b)
        try remove(a, id: item.id); _ = try sync(a, b)
        expect(try LibraryArchive.read(from: b).items.isEmpty, "删除传播到未改端")
        _ = try sync(c, b)
        expect(try LibraryArchive.read(from: c).items.isEmpty, "离线第三端不会复活已删除作品")
        expect(try sync(a, b).unchanged, "传播删除后重复同步收敛")
    } catch { expect(false, "删除传播失败：\(error)") }
    do {
        let a = try folder(), b = try folder()
        let item = makeItem(title: "删除修改冲突", poster: Data([1]))
        try LibraryArchive.commit(LibraryDocument(items: [item]), to: a); _ = try sync(a, b)
        try remove(a, id: item.id); try edit(b, id: item.id) { $0.rating = 10 }
        let pending = try LibrarySyncCoordinator.prepare(local: a, remote: b)
        expectEqual(pending.merged.conflicts.count, 1, "删除与离线修改需要确认")
        let version = try LibrarySyncDisk.version(in: b)
        rejects("未解决冲突不能提交") { _ = try LibrarySyncCoordinator.apply(pending, choices: [:]) }
        expectEqual(try LibrarySyncDisk.version(in: b), version, "取消或未解决冲突不写盘")
        _ = try LibrarySyncCoordinator.apply(pending, choices: [item.id.uuidString: true])
        expectEqual(try LibraryArchive.read(from: a).items.first?.rating, 10, "选择保留恢复另一端修改")
        expect(try sync(a, b).unchanged, "保留决定不再次弹出同一删除冲突")
        try remove(a, id: item.id); try edit(b, id: item.id) { $0.review = "仍然修改" }
        let again = try LibrarySyncCoordinator.prepare(local: a, remote: b)
        expectEqual(again.merged.conflicts.count, 1, "再次删除与新修改产生新冲突")
        _ = try LibrarySyncCoordinator.apply(again, choices: [item.id.uuidString: false])
        expect(try LibraryArchive.read(from: b).items.isEmpty, "选择删除传播到两端")
        expect(try sync(a, b).unchanged, "删除决定不重复产生冲突")
    } catch { expect(false, "删除冲突失败：\(error)") }
    do {
        let a = try folder(), b = try folder()
        var x = makeItem(title: "同一电影", id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, poster: Data([1]))
        var y = makeItem(title: "同一电影", id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, poster: Data([2]))
        x.source = MediaSource(tmdb: .movie(id: 123), language: "zh-CN", fetchedAt: x.updatedAt)
        y.source = x.source; y.updatedAt = y.updatedAt.addingTimeInterval(1); y.review = "较新的短评"
        let manualA = makeItem(title: "同名手动"), manualB = makeItem(title: "同名手动")
        try LibraryArchive.commit(LibraryDocument(items: [x, manualA]), to: a)
        try LibraryArchive.commit(LibraryDocument(items: [y, manualB]), to: b)
        _ = try sync(a, b)
        let result = try LibraryArchive.read(from: a)
        expectEqual(result.items.count, 3, "TMDb 合并，手动同名保持两条")
        let movie = result.items.first { $0.source != nil }!
        expectEqual(movie.id, x.id, "重复作品采用稳定最小 UUID")
        expectEqual(movie.poster, Data([2]), "归并 UUID 后选中附件正确安装")
        expectEqual(movie.review, "较新的短评", "重复作品按字段合并")
        expectEqual(try LibrarySyncDisk.read(from: b).state.aliases[y.id.uuidString], x.id.uuidString, "别名持久化")
        expect(try sync(b, a).unchanged, "反向同步重复身份结果收敛")
        try remove(b, id: x.id); _ = try sync(a, b)
        expectEqual(try LibraryArchive.read(from: a).items.count, 2, "归并后的删除不留下重复作品")
    } catch { expect(false, "身份归并失败：\(error)") }
    do {
        let a = try folder(), b = try folder()
        let x = makeItem(title: "A", rating: 10), y = makeItem(title: "B", rating: 10), z = makeItem(title: "C", rating: 10)
        var watchingA = makeItem(title: "在看 A"), watchingB = makeItem(title: "在看 B")
        watchingA.status = .watching; watchingB.status = .watching
        try LibraryArchive.commit(LibraryDocument(items: [x, y, z, watchingA, watchingB]), to: a); _ = try sync(a, b)
        var left = try LibraryArchive.read(from: a, hydrate: false)
        let contentDate = left.items.first { $0.id == x.id }!.updatedAt
        try left.reorderHome([z.id, y.id, x.id], status: .watched); left.revision += 1
        try LibraryArchive.commit(left, to: a)
        var right = try LibraryArchive.read(from: b, hydrate: false)
        try right.reorderHome([watchingB.id, watchingA.id], status: .watching); right.revision += 1
        try LibraryArchive.commit(right, to: b)
        _ = try sync(a, b)
        let result = try LibraryArchive.read(from: a)
        expectEqual(result.homeItems.filter { $0.status == .watched }.map(\.id), [z.id, y.id, x.id], "合并看过分类排序")
        expectEqual(result.homeItems.filter { $0.status == .watching }.map(\.id), [watchingB.id, watchingA.id], "不同分类排序互不覆盖")
        expectEqual(result.items.first { $0.id == x.id }!.updatedAt, contentDate, "排序不改变内容时间")
        var rankingA = result; try rankingA.reorder([y.id, z.id, x.id], ranking: true); rankingA.revision += 1; try LibraryArchive.commit(rankingA, to: a)
        var rankingB = try LibraryArchive.read(from: b); try rankingB.reorder([x.id, z.id, y.id], ranking: true); rankingB.revision += 1; try LibraryArchive.commit(rankingB, to: b)
        _ = try sync(a, b)
        expectEqual(try LibraryArchive.read(from: a).rankingOrder, [x.id, z.id, y.id], "同评分组较晚排序优先")
        var fresh = try LibraryArchive.read(from: a)
        let new = makeItem(title: "新添加", rating: 10, updatedAt: Date())
        try fresh.upsert(new); fresh.revision += 1; try LibraryArchive.commit(fresh, to: a)
        _ = try sync(a, b)
        expectEqual(try LibraryArchive.read(from: b).homeItems.first?.id, new.id, "同步保留新条目组首位置")
        expect(try sync(a, b).unchanged, "排序及新增合并后收敛")
    } catch { expect(false, "排序合并失败：\(error)") }
    do {
        let a = try folder(), b = try folder()
        let item = makeItem(title: "中断恢复", poster: Data([1]))
        try LibraryArchive.commit(LibraryDocument(items: [item]), to: a); _ = try sync(a, b)
        try edit(a, id: item.id) { $0.rating = 8 }; try edit(b, id: item.id) { $0.review = "离线修改" }
        let prepared = try LibrarySyncCoordinator.prepare(local: a, remote: b)
        let before = try LibrarySyncDisk.version(in: a)
        rejects("本机安装中断抛错") { _ = try LibrarySyncCoordinator.apply(prepared, choices: [:], failLocalAfterInstall: 1) }
        expectEqual(try LibrarySyncDisk.version(in: a), before, "本机失败恢复原元数据")
        let resumed = try LibrarySyncCoordinator.prepare(local: a, remote: b)
        expect(resumed.resumed, "两端提交中断保留检查点")
        _ = try LibrarySyncCoordinator.apply(resumed, choices: [:])
        let result = try LibraryArchive.read(from: a)
        expect(result.items[0].rating == 8 && result.items[0].review == "离线修改", "恢复不丢两端修改")
        expect(try sync(a, b).unchanged, "恢复完成后收敛")
        let stale = try LibrarySyncCoordinator.prepare(local: a, remote: b)
        try edit(b, id: item.id) { $0.rating = 10 }
        rejects("远端预览后变化拒绝过期提交") { _ = try LibrarySyncCoordinator.apply(stale, choices: [:]) }
        expectEqual(try LibraryArchive.read(from: b).items[0].rating, 10, "过期提交不覆盖远端新修改")
    } catch { expect(false, "检查点恢复失败：\(error)") }
    do {
        let a = try folder(), b = try folder()
        let item = makeItem(title: "校验失败", poster: Data([1]))
        try LibraryArchive.commit(LibraryDocument(items: [item]), to: a); _ = try sync(a, b)
        try edit(b, id: item.id) { $0.poster = Data([2]) }
        let before = try LibrarySyncDisk.version(in: a)
        try Data([3]).write(to: b.appendingPathComponent(AttachmentKind.poster.path(for: item.id)))
        rejects("变化图片摘要错误拒绝提交") { _ = try sync(a, b) }
        expectEqual(try LibrarySyncDisk.version(in: a), before, "图片校验失败不修改本机")
        try manager.removeItem(at: b.appendingPathComponent(AttachmentKind.poster.path(for: item.id)))
        rejects("缺失附件拒绝同步") { _ = try sync(a, b) }
        try Data("broken".utf8).write(to: b.appendingPathComponent(LibrarySyncState.fileName))
        rejects("损坏清单拒绝覆盖") { _ = try sync(a, b) }
        expectEqual(try LibrarySyncDisk.version(in: a), before, "损坏清单不修改本机")
    } catch { expect(false, "校验测试失败：\(error)") }
    do {
        // Exercise legacy indexing without a sidecar, then the zero-read fast path.
        let a = try folder(), b = try folder()
        let item = makeItem(title: "旧文件夹", poster: Data([1, 2]))
        let doc = LibraryDocument(items: [item])
        try manager.createDirectory(at: b.appendingPathComponent("Posters"), withIntermediateDirectories: true)
        try doc.encoded().write(to: b.appendingPathComponent(LibraryFiles.libraryFileName))
        try item.poster!.write(to: b.appendingPathComponent(AttachmentKind.poster.path(for: item.id)))
        try LibraryArchive.commit(LibraryDocument(), to: a)
        let first = try sync(a, b)
        expect(first.readBytes >= 2 && first.transferred == 1, "旧文件夹首轮读取并建立摘要")
        expect(try sync(a, b).unchanged, "旧文件夹建立清单后增量同步")
        // Valid but stale metadata is rebuilt, preserving field clocks and indexing all files.
        var externallyEdited = try LibraryArchive.read(from: b, hydrate: false)
        externallyEdited.items[0].rating = 6
        try externallyEdited.encoded().write(to: b.appendingPathComponent(LibraryFiles.libraryFileName))
        let localVersion = try LibrarySyncDisk.version(in: a)
        rejects("有效清单与 JSON 不匹配时拒绝不一致快照") { _ = try sync(a, b) }
        expectEqual(try LibrarySyncDisk.version(in: a), localVersion, "不一致快照不覆盖本机资料")
        try manager.removeItem(at: b.appendingPathComponent(LibrarySyncState.fileName))
        _ = try sync(a, b)
        expectEqual(try LibraryArchive.read(from: a).items[0].rating, 6, "清单缺失时通过基线重建与重新校验")
    } catch { expect(false, "旧清单兼容失败：\(error)") }
    do {
        // Crash journals survive process termination; recovery runs before reading JSON.
        let a = try folder()
        let item = makeItem(title: "文件事务", poster: Data([1]))
        try LibraryArchive.commit(LibraryDocument(items: [item]), to: a)
        let before = try LibrarySyncDisk.version(in: a)
        let json = a.appendingPathComponent(LibraryFiles.libraryFileName)
        let journal = a.appendingPathComponent(".sync-transaction-" + UUID().uuidString)
        try manager.createDirectory(at: journal.appendingPathComponent("old"), withIntermediateDirectories: true)
        try Data(LibraryFileTransaction.ownerID.utf8).write(to: journal.appendingPathComponent("owner"))
        try manager.copyItem(at: json, to: journal.appendingPathComponent("old/" + LibraryFiles.libraryFileName))
        try SyncCoding.encode(LibraryFileTransaction.Journal(paths: [LibraryFiles.libraryFileName], originals: [LibraryFiles.libraryFileName])).write(to: journal.appendingPathComponent("journal.json"))
        try Data("broken".utf8).write(to: json)
        _ = try LibraryArchive.read(from: a)
        expectEqual(try LibrarySyncDisk.version(in: a), before, "重启后从文件级事务恢复原资料库")
        expect(!manager.fileExists(atPath: journal.path), "恢复成功移除事务目录")
        let foreign = a.appendingPathComponent(".sync-transaction-" + UUID().uuidString)
        try manager.createDirectory(at: foreign.appendingPathComponent("old"), withIntermediateDirectories: true)
        try Data(UUID().uuidString.utf8).write(to: foreign.appendingPathComponent("owner"))
        try Data("another device's older version".utf8).write(to: foreign.appendingPathComponent("old/" + LibraryFiles.libraryFileName))
        try SyncCoding.encode(LibraryFileTransaction.Journal(paths: [LibraryFiles.libraryFileName], originals: [LibraryFiles.libraryFileName])).write(to: foreign.appendingPathComponent("journal.json"))
        _ = try LibraryArchive.read(from: a)
        expectEqual(try LibrarySyncDisk.version(in: a), before, "不回滚文件提供商送达的其他设备未完成事务")
        expect(manager.fileExists(atPath: foreign.path), "保留其他设备的回滚点直到其自行清理")
        let writes = [AttachmentKind.poster.path(for: item.id): Data([2]), LibraryFiles.libraryFileName: Data("new".utf8), LibrarySyncState.fileName: Data("new state".utf8)]
        for stage in 1...3 {
            rejects("第 \(stage) 个文件安装失败") { try LibraryFileTransaction.commit(writes: writes, deleting: [], to: a, failAfterInstall: stage) }
            expectEqual(try LibrarySyncDisk.version(in: a), before, "第 \(stage) 阶段恢复 JSON 和清单")
            expectEqual(try LibraryArchive.read(from: a).items[0].poster, Data([1]), "第 \(stage) 阶段恢复图片")
        }
    } catch { expect(false, "文件事务失败：\(error)") }
    do {
        let a = try folder(), b = try folder(), c = try folder()
        let item = makeItem(title: "清单恢复", poster: Data([1, 2]))
        try LibraryArchive.commit(LibraryDocument(items: [item]), to: a); _ = try sync(a, b)
        try Data("damaged manifest".utf8).write(to: b.appendingPathComponent(LibrarySyncState.fileName))
        let repaired = try sync(a, b)
        expectEqual(repaired.readBytes, 2, "清单损坏后通过可信基线重新读取并校验图片")
        expectEqual(repaired.transferred, 0, "重建相同图片指纹不重传附件")
        expect(try sync(a, b).unchanged, "修复清单后恢复零读写路径")
        try remove(a, id: item.id); _ = try sync(a, b)
        try manager.removeItem(at: b.appendingPathComponent(LibrarySyncState.fileName))
        _ = try sync(a, b)
        expect(try LibrarySyncDisk.read(from: b).state.deletions[item.id.uuidString] != nil, "清单丢失时基线保留删除历史")
        try manager.removeItem(at: b.appendingPathComponent(LibraryFiles.libraryFileName))
        rejects("已有基线的远端 JSON 丢失不能推断为整库删除") { _ = try sync(a, b) }
        rejects("同步目标不可等于本机资料库目录") { _ = try sync(a, a) }
        rejects("未初始化本机资料库拒绝同步") { _ = try sync(c, a) }
    } catch { expect(false, "可信基线恢复失败：\(error)") }
    do {
        let a = try folder(), b = try folder()
        var item = makeItem(title: "资料字段合并")
        item.metadata = MediaMetadata(originalTitle: "Original", overview: "原简介", genres: ["动画"])
        try LibraryArchive.commit(LibraryDocument(items: [item]), to: a); _ = try sync(a, b)
        try edit(a, id: item.id) { $0.metadata?.overview = "本机简介" }
        try edit(b, id: item.id) { $0.metadata?.genres = ["剧情", "冒险"] }
        _ = try sync(a, b)
        let merged = try LibraryArchive.read(from: a).items[0]
        expectEqual(merged.metadata?.overview, "本机简介", "作品资料各属性独立合并")
        expectEqual(merged.metadata?.genres, ["剧情", "冒险"], "数组字段作为完整值合并")
        let left = try LibrarySyncDisk.read(from: a), right = try LibrarySyncDisk.read(from: b)
        var x = left, y = right
        x.state.records[item.id.uuidString]!.entry.rating = 3
        y.state.records[item.id.uuidString]!.entry.rating = 9
        let timestamp = Date(timeIntervalSince1970: 2_000_000_000)
        x.state.records[item.id.uuidString]!.fields["personal.rating"] = SyncStamp(date: timestamp, operation: "A")
        y.state.records[item.id.uuidString]!.fields["personal.rating"] = SyncStamp(date: timestamp, operation: "B")
        let forward = try LibrarySyncMerger.merge(x, y), reverse = try LibrarySyncMerger.merge(y, x)
        expectEqual(forward.document.items[0].rating, 9, "相同时间按稳定操作标识打破平局")
        expectEqual(try forward.document.encoded(), try reverse.document.encoded(), "反向合并同时间结果相同")
        y.state.records[item.id.uuidString]!.fields["personal.rating"] = SyncStamp(date: timestamp, operation: "A")
        let collisionA = try LibrarySyncMerger.merge(x, y), collisionB = try LibrarySyncMerger.merge(y, x)
        expectEqual(try collisionA.document.encoded(), try collisionB.document.encoded(), "相同操作标识也确定性收敛")
        var invalid = left.state
        invalid.aliases[item.id.uuidString] = item.id.uuidString
        rejects("拒绝循环 UUID 别名") { try LibrarySyncDisk.validate(invalid) }
        invalid = left.state; invalid.records[item.id.uuidString]!.fields.removeValue(forKey: "title")
        rejects("拒绝缺失字段时钟") { try LibrarySyncDisk.validate(invalid) }
        invalid = left.state; invalid.ranking["99"] = SyncOrder(ids: [item.id], stamp: SyncStamp(date: timestamp, operation: "bad"))
        rejects("拒绝非法同步评分组") { try LibrarySyncDisk.validate(invalid) }
        rejects("拒绝事务目录逃逸路径") { try LibraryFileTransaction.commit(writes: ["../outside.jpg": Data([1])], deleting: [], to: a) }
    } catch { expect(false, "资料字段和平局测试失败：\(error)") }
    do {
        let a = try folder(), b = try folder()
        let item = makeItem(title: "中断后继续编辑", poster: Data([1]))
        try LibraryArchive.commit(LibraryDocument(items: [item]), to: a); _ = try sync(a, b)
        try edit(a, id: item.id) { $0.rating = 8 }; try edit(b, id: item.id) { $0.review = "远端短评" }
        let preparation = try LibrarySyncCoordinator.prepare(local: a, remote: b)
        rejects("中断留下检查点") { _ = try LibrarySyncCoordinator.apply(preparation, choices: [:], failLocalAfterInstall: 1) }
        try edit(a, id: item.id) { $0.rating = 10 }
        let recomputed = try LibrarySyncCoordinator.prepare(local: a, remote: b)
        expect(!recomputed.resumed, "中断后有新编辑重新比较而非覆盖检查点")
        _ = try LibrarySyncCoordinator.apply(recomputed, choices: [:])
        let final = try LibraryArchive.read(from: a).items[0]
        expect(final.rating == 10 && final.review == "远端短评", "重算保留中断后的编辑和已提交的远端内容")
    } catch { expect(false, "中断后编辑测试失败：\(error)") }

    do {
        let a = try folder(), b = try folder()
        let item = makeItem(title: "同版本附件刷新", poster: Data([1]))
        try LibraryArchive.commit(LibraryDocument(items: [item]), to: a); _ = try sync(a, b)
        let prior = try LibrarySyncDisk.read(from: a)
        var changed = try LibraryArchive.read(from: b)
        changed.items[0].poster = Data([2]) // Deliberately keep both JSON revision and updatedAt equal.
        try LibraryArchive.commit(changed, to: b)
        let pending = try LibrarySyncCoordinator.prepare(local: a, remote: b)
        expect(pending.merged.document.revision > prior.document.revision, "同版本更换附件仍递增 revision 以刷新可见图片")
        _ = try LibrarySyncCoordinator.apply(pending, choices: [:])
        expectEqual(try LibraryArchive.read(from: a).items[0].poster, Data([2]), "同版本附件更新正确落盘")
        expect(try sync(a, b).unchanged, "附件刷新后的版本不会反复递增")
        let revision = try LibrarySyncDisk.read(from: a).document.revision
        expectEqual(try LibrarySyncDisk.read(from: b).document.revision, revision, "双端更新保持共同 revision")
    } catch { expect(false, "同版本附件刷新测试失败：\(error)") }

}
