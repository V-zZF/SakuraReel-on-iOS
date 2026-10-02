import Foundation

actor FixtureTransport: TMDbHTTPTransport {
    var requests: [URLRequest] = []
    var status = 200
    var retries = 0
    var retryAfter = "0"
    var optionalFailure = false
    var malformed = false
    func setup(status: Int = 200, retries: Int = 0, retryAfter: String = "0", optionalFailure: Bool = false, malformed: Bool = false) {
        self.status = status; self.retries = retries; self.retryAfter = retryAfter
        self.optionalFailure = optionalFailure; self.malformed = malformed
    }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let path = request.url!.path
        let code = retries > 0 ? 429 : (optionalFailure && (path.hasSuffix("/credits") || path.hasSuffix("/images")) ? 500 : status)
        if retries > 0 { retries -= 1 }
        let body: String
        if malformed { body = "invalid" }
        else if path.hasSuffix("/configuration") {
            body = #"{"images":{"secure_base_url":"https://image.tmdb.org/t/p/","poster_sizes":["w185","w780","original"],"backdrop_sizes":["w1280","original"],"logo_sizes":["w500","original"],"profile_sizes":["w185","original"],"still_sizes":["w300","original"]}}"#
        } else if path.contains("/search/") {
            body = #"{"page":1,"total_pages":2,"results":[{"id":7,"title":"Movie","name":"Series","original_title":null,"overview":null,"release_date":"2001-02-03","poster_path":"/poster.jpg"}]}"#
        } else if path.hasSuffix("/images") { body = #"{"posters":[],"backdrops":[],"logos":[]}"# }
        else if path.hasSuffix("/credits") { body = #"{"cast":[],"crew":[]}"# }
        else if path.contains("/season/") {
            body = #"{"id":70,"name":"Season 1","overview":null,"air_date":"2001-02-03","episodes":[{"id":71,"name":"Episode 1","episode_number":1}]}"#
        } else {
            body = #"{"id":7,"title":"Movie","name":"Series","original_title":null,"original_name":"Original","overview":"Overview","release_date":"2001-02-03","poster_path":"/poster.jpg","vote_average":7.2,"seasons":[{"id":70,"name":"Season 1","season_number":1}]}"#
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Retry-After": retryAfter])!)
    }
    func count(path: String? = nil) -> Int { requests.filter { path == nil || $0.url?.path == path }.count }
    func lastHost() -> String? { requests.last?.url?.host }
}
actor NetworkScenarioTransport: TMDbHTTPTransport {
    enum Action: Sendable { case fail(URLError.Code), status(Int), blocked(Int) }
    var actions: [String: [Action]]
    var requests: [URLRequest] = []
    init(_ actions: [String: [Action]]) { self.actions = actions }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let host = request.url!.host!
        let action = actions[host]?.isEmpty == false ? actions[host]!.removeFirst() : .status(200)
        switch action {
        case .fail(let code): throw URLError(code)
        case .status(let code):
            let body = [401, 403].contains(code) ? "{\"status_code\":7,\"success\":false}" : "{}"
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Retry-After": "0"])!)
        case .blocked(let code):
            return (Data("<html>proxy denied</html>".utf8), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
        }
    }
    func hosts() -> [String] { requests.compactMap { $0.url?.host } }
    func latest() -> URLRequest? { requests.last }
}

actor ConnectionBox {
    var value = TMDbConnection(key: "fixture-only-key", generation: UUID())
    func read() -> TMDbConnection { value }
    func changeHost() { value = TMDbConnection(key: "fixture-new-key", host: "owned.example.com", generation: UUID()) }
}
actor FakeService: TMDbServing {
    var failedPage = false
    func search(_ query: String, type: TMDbMediaType, language: String, page: Int) async throws -> TMDbSearchPage {
        if query == "old" || (query == "pagecancel" && page == 2) {
            await Task.detached { try? await Task.sleep(for: .milliseconds(180)) }.value
        }
        if page == 2 && !failedPage { failedPage = true; throw TMDbError.network }
        let title = "\(query):\(language):\(page)"
        return TMDbSearchPage(results: [TMDbSearchResult(source: MediaSource(tmdb: type == .movie ? .movie(id: page) : .series(id: page), language: language, fetchedAt: Date()), title: title)], page: page, totalPages: 2)
    }
    func details(_ source: MediaSource) async throws -> TMDbImportDraft {
        TMDbImportDraft(source: source, title: "Title", metadata: MediaMetadata(overview: "Overview", posterPath: "/failed.jpg"))
    }
    func imageURL(_ path: String, role: String, width: Int) async -> URL? { URL(string: "https://image.tmdb.org" + path) }
    func validate(_ connection: TMDbConnection) async throws {}
}
struct FailingImages: TMDbImageLoading {
    func load(_ url: URL, pixels: Int, kind: String) async throws -> Data { throw TMDbError.network }
}
struct OutOfOrderImages: TMDbImageLoading {
    func load(_ url: URL, pixels: Int, kind: String) async throws -> Data {
        if url.path == "/old" { await Task.detached { try? await Task.sleep(for: .milliseconds(120)) }.value }
        return Data(url.path.utf8)
    }
}

actor ProducerProbe {
    var started = 0
    var cancelled = 0
    func work() async throws -> Int {
        started += 1
        do { try await Task.sleep(for: .seconds(10)); return 9 }
        catch { cancelled += 1; throw error }
    }
}

@main struct TMDbServiceTests {
    @MainActor static func main() async throws {
        var checks = 0
        func expect(_ condition: Bool, _ label: String) {
            checks += 1
            if !condition { fatalError("FAILED: " + label) }
        }
        let directHost = try TMDbRequestClient.validatedHost(nil)
        expect(directHost == "api.themoviedb.org", "nil proxy means explicit direct connection")
        let proxyHost = try TMDbRequestClient.validatedHost("https://owned.example.com/")
        expect(proxyHost == "owned.example.com", "proxy rewrites only host")
        for invalid in ["", "http://owned.example.com", "https://owned.example.com/path", "https://key@owned.example.com"] {
            do { _ = try TMDbRequestClient.validatedHost(invalid); expect(false, "expected invalid host") }
            catch { expect(error as? TMDbError == .invalidProxy, "invalid proxy never falls back to unselected line") }
        }
        // AniShelf relay pair is explicit; credentials never fan out to unrelated hosts.
        let relayHost = TMDbRoutes.aniShelf[0]
        let backupHost = TMDbRoutes.aniShelf[1]
        let relayConnection = TMDbConnection(key: "fixture-route-key", host: relayHost, generation: UUID(), fallbackHosts: [backupHost])
        let relayTransport = NetworkScenarioTransport([relayHost: [.fail(.secureConnectionFailed)]])
        let relayClient = TMDbRequestClient(transport: relayTransport, sleep: { _ in })
        _ = try await relayClient.data(path: "/search/movie", query: [URLQueryItem(name: "query", value: "电影 & title")], connection: relayConnection)
        let relayHosts = await relayTransport.hosts()
        expect(relayHosts == [relayHost, backupHost], "TLS failure switches only within the selected AniShelf relay pair")
        let encodedRequest = await relayTransport.latest()!
        let queryValues = URLComponents(url: encodedRequest.url!, resolvingAgainstBaseURL: false)!.queryItems!
        expect(encodedRequest.url?.path == "/3/search/movie" && queryValues.contains(URLQueryItem(name: "query", value: "电影 & title")), "relay rewriting preserves API path and encoded search query")
        expect(queryValues.contains(URLQueryItem(name: "api_key", value: "fixture-route-key")), "selected relay receives the configured credential")
        _ = try await relayClient.data(path: "/configuration", connection: relayConnection)
        let reusedHosts = await relayTransport.hosts()
        expect(reusedHosts == [relayHost, backupHost, backupHost], "subsequent requests reuse the working relay")
        let directConnection = TMDbConnection(key: "fixture-route-key", generation: UUID())
        let tlsTransport = NetworkScenarioTransport([TMDbRoutes.direct: [.fail(.secureConnectionFailed)]])
        do {
            _ = try await TMDbRequestClient(transport: tlsTransport, sleep: { _ in }).data(path: "/configuration", connection: directConnection)
            expect(false, "expected TLS failure")
        } catch { expect(error as? TMDbError == .networkFailure(-1200), "TLS error is preserved without URLs or credentials") }
        let tlsHosts = await tlsTransport.hosts()
        expect(tlsHosts == [TMDbRoutes.direct], "direct mode never silently forwards the credential to a relay")
        let transient = NetworkScenarioTransport([TMDbRoutes.direct: [.fail(.networkConnectionLost), .status(200)]])
        _ = try await TMDbRequestClient(transport: transient, sleep: { _ in }).data(path: "/configuration", connection: directConnection)
        let transientHosts = await transient.hosts()
        expect(transientHosts.count == 2, "dropped connection retries once")
        let timeout = NetworkScenarioTransport([TMDbRoutes.direct: [.fail(.timedOut), .fail(.timedOut)]])
        do {
            _ = try await TMDbRequestClient(transport: timeout, sleep: { _ in }).data(path: "/configuration", connection: directConnection)
            expect(false, "expected timeout")
        } catch { expect(error as? TMDbError == .networkFailure(-1001), "bounded timeout retains the specific failure") }
        let timeoutHosts = await timeout.hosts()
        expect(timeoutHosts.count == 2, "timeout retries are bounded")
        for status in [401, 403, 404, 429] {
            let failed = NetworkScenarioTransport([relayHost: Array(repeating: .status(status), count: 3)])
            do {
                _ = try await TMDbRequestClient(transport: failed, sleep: { _ in }).data(path: "/configuration", connection: relayConnection)
                expect(false, "expected terminal status")
            } catch {
                let expected: TMDbError = status == 404 ? .notFound : status == 429 ? .rateLimited : .authentication
                expect(error as? TMDbError == expected, "authentication, missing resource and rate limit preserve their error")
            }
            let attempted = await failed.hosts()
            expect(attempted.allSatisfy { $0 == relayHost }, "terminal HTTP status never bypasses limits by switching hosts")
        }
        let unavailable = NetworkScenarioTransport([relayHost: Array(repeating: .status(503), count: 3)])
        _ = try await TMDbRequestClient(transport: unavailable, sleep: { _ in }).data(path: "/configuration", connection: relayConnection)
        let unavailableHosts = await unavailable.hosts()
        expect(unavailableHosts == [relayHost, relayHost, relayHost, backupHost], "transient server failure has bounded retries then relay fallback")
        let blockedRelay = NetworkScenarioTransport([relayHost: [.blocked(403)]])
        _ = try await TMDbRequestClient(transport: blockedRelay, sleep: { _ in }).data(path: "/configuration", connection: relayConnection)
        let blockedHosts = await blockedRelay.hosts()
        expect(blockedHosts == [relayHost, backupHost], "non-TMDb proxy rejection tries the selected backup")
        let bothBlocked = NetworkScenarioTransport([relayHost: [.blocked(403)], backupHost: [.blocked(403)]])
        do {
            _ = try await TMDbRequestClient(transport: bothBlocked, sleep: { _ in }).data(path: "/configuration", connection: relayConnection)
            expect(false, "expected proxy rejection")
        } catch { expect(error as? TMDbError == .proxyRejected(403), "proxy rejection is distinct from a bad API key") }
        let cancelledTransport = NetworkScenarioTransport([relayHost: [.fail(.cancelled)]])
        do {
            _ = try await TMDbRequestClient(transport: cancelledTransport, sleep: { _ in }).data(path: "/configuration", connection: relayConnection)
            expect(false, "expected cancellation")
        } catch { expect(error is CancellationError, "cancellation remains cancellation") }
        let cancelledHosts = await cancelledTransport.hosts()
        expect(cancelledHosts == [relayHost], "cancellation does not start backup requests")
        let malicious = TMDbConnection(key: "fixture-route-key", host: relayHost, generation: UUID(), fallbackHosts: ["unrelated.example"])
        do {
            _ = try await relayClient.data(path: "/configuration", connection: malicious)
            expect(false, "expected invalid route")
        } catch { expect(error as? TMDbError == .invalidProxy, "unapproved alternate hosts are rejected before requesting") }
        let routeState = TMDbRouteState()
        let routeDate = Date(timeIntervalSince1970: 1000)
        await routeState.succeeded(backupHost, generation: relayConnection.generation, now: routeDate)
        let expired = await routeState.ordered(TMDbRoutes.aniShelf, generation: relayConnection.generation, now: routeDate.addingTimeInterval(301))
        expect(expired == TMDbRoutes.aniShelf, "working relay preference expires")
        let changedGeneration = await routeState.ordered(TMDbRoutes.aniShelf, generation: UUID(), now: routeDate)
        expect(changedGeneration == TMDbRoutes.aniShelf, "credential changes do not inherit route preference")
        let configuration = TMDbURLTransport.configuration()
        expect(configuration.urlCache == nil && configuration.httpCookieStorage == nil, "API session avoids credential-bearing disk caches and cookies")
        expect(configuration.timeoutIntervalForRequest == 15 && configuration.timeoutIntervalForResource == 30, "network requests have finite deadlines")
        let redirectOrigin = URL(string: "https://api.themoviedb.org/3/configuration")!
        expect(TMDbURLTransport.permitsRedirect(from: redirectOrigin, to: URL(string: "https://api.themoviedb.org/3/other")), "same-authority HTTPS redirect is permitted")
        expect(!TMDbURLTransport.permitsRedirect(from: redirectOrigin, to: URL(string: "https://unrelated.example/3/configuration")), "credential cannot follow a cross-host redirect")
        expect(!TMDbURLTransport.permitsRedirect(from: redirectOrigin, to: URL(string: "http://api.themoviedb.org/3/configuration")), "credential cannot follow a TLS downgrade")
        expect(!TMDbURLTransport.permitsRedirect(from: redirectOrigin, to: URL(string: "https://api.themoviedb.org:8443/3/configuration")), "credential cannot follow a different-port redirect")
        let transport = FixtureTransport()
        let box = ConnectionBox()
        let client = TMDbRequestClient(transport: transport, sleep: { _ in })
        let service = TMDbService(client: client, connection: { await box.read() })
        let page = try await service.search("title", type: .movie, language: "zh-CN", page: 1)
        expect(page.totalPages == 2 && page.results[0].overview == nil, "nullable fields and pagination")
        let source = MediaSource(tmdb: .movie(id: 7), language: "zh-CN", fetchedAt: Date())
        await transport.setup(optionalFailure: true)
        let draft = try await service.details(source)
        expect(draft.title == "Movie" && draft.metadata.tmdbRating == 7.2, "basic details survive optional failures")
        expect(draft.warnings.count == 2, "optional failures produce warnings")
        _ = try await service.details(source)
        let detailsCount = await transport.count(path: "/3/movie/7")
        expect(detailsCount == 1, "reuse fetched details")
        let cachedURL = await service.cachedImageURL("/poster.jpg", role: "poster", width: 600)
        let readOnlyConfigurationCount = await transport.count(path: "/3/configuration")
        expect(cachedURL?.host == "image.tmdb.org" && readOnlyConfigurationCount == 0, "read-only detail image URLs never send authenticated API requests")
        async let first = service.imageURL("/poster.jpg", role: "poster", width: 600)
        async let second = service.imageURL("/logo.svg", role: "logo", width: 500)
        let urls = await (first, second)
        expect(urls.0?.path == "/t/p/w780/poster.jpg" && urls.1?.path.hasSuffix(".png") == true, "image sizes and PNG fallback")
        let configurationCount = await transport.count(path: "/3/configuration")
        expect(configurationCount == 1, "configuration in-flight merging")
        await box.changeHost()
        _ = try await service.search("title", type: .series, language: "en-US", page: 1)
        let host = await transport.lastHost()
        expect(host == "owned.example.com", "configuration immediately changes selected API host")
        let season = MediaSource(tmdb: .season(id: 70, seriesID: 7, number: 1), language: "en-US", fetchedAt: Date())
        let seasonDraft = try await service.details(season)
        expect(seasonDraft.title == "Movie · Season 1" && seasonDraft.metadata.episodes.count == 1, "season uses parent and season summary")
        for (status, expected) in [(401, TMDbError.authentication), (404, .notFound), (500, .server(500))] {
            await transport.setup(status: status)
            do { try await service.validate(await box.read()); expect(false, "expected HTTP error") }
            catch { expect(error as? TMDbError == expected, "typed HTTP error") }
        }
        await transport.setup(malformed: true)
        do { _ = try await service.search("x", type: .movie, language: "en-US", page: 1); expect(false, "expected decode error") }
        catch { expect(error as? TMDbError == .decoding, "typed decode error") }
        let beforeRetry = await transport.count()
        await transport.setup(retries: 2)
        try await service.validate(await box.read())
        let afterRetry = await transport.count()
        expect(afterRetry - beforeRetry == 3, "429 bounded retries")
        await transport.setup(retries: 9, retryAfter: "31")
        let beforeLong = await transport.count()
        do { try await service.validate(await box.read()); expect(false, "expected rate limit") }
        catch { expect(error as? TMDbError == .rateLimited, "long delay surfaces rate limit") }
        let afterLong = await transport.count()
        expect(afterLong - beforeLong == 1, "no early retry for long Retry-After")
        await transport.setup(retries: 9)
        let beforeExhaustion = await transport.count()
        do { try await service.validate(await box.read()); expect(false, "expected exhausted retries") }
        catch { expect(error as? TMDbError == .rateLimited, "exhausted retries error") }
        let afterExhaustion = await transport.count()
        expect(afterExhaustion - beforeExhaustion == 3, "429 never exceeds two retries")
        let beforeMissing = await transport.count()
        do { try await service.validate(TMDbConnection(key: "", generation: UUID())); expect(false, "expected missing key") }
        catch { expect(error as? TMDbError == .missingKey, "missing key typed error") }
        let afterMissing = await transport.count()
        expect(beforeMissing == afterMissing, "missing key never sends request")
        let pool = SharedTaskPool<Int>()
        let probe = ProducerProbe()
        let consumer1 = Task { try await pool.value(for: "same") { try await probe.work() } }
        let consumer2 = Task { try await pool.value(for: "same") { try await probe.work() } }
        try await Task.sleep(for: .milliseconds(30))
        consumer1.cancel()
        try await Task.sleep(for: .milliseconds(30))
        let notCancelled = await probe.cancelled
        expect(notCancelled == 0, "one cancellation preserves other coalesced consumer")
        consumer2.cancel()
        _ = try? await consumer1.value; _ = try? await consumer2.value
        let cancellationCount = await probe.cancelled
        let producerCount = await probe.started
        expect(cancellationCount == 1 && producerCount == 1, "last consumer cancels single shared producer")
        let now = Date(timeIntervalSince1970: 0)
        expect(TMDbRequestClient.retryDelay("Thu, 01 Jan 1970 00:00:05 GMT", now: now, attempt: 0) == 5, "HTTP date Retry-After")
        expect(TMDbRequestClient.retryDelay("2", now: now, attempt: 0) == 2, "numeric Retry-After")
        let fake = FakeService()
        let search = TMDbSearchModel(service: fake)
        let old = Task { await search.search(query: "old", language: "zh-CN", type: "movie") }
        try await Task.sleep(for: .milliseconds(340))
        let latest = Task { await search.search(query: "new", language: "ja-JP", type: "series") }
        await latest.value; await old.value
        expect(search.movies.results.isEmpty && search.series.results.first?.title == "new:ja-JP:1", "obsolete query language type cannot publish")
        await search.load(.series)
        expect(search.series.results.count == 1 && search.series.error != nil, "failed page preserves results")
        await search.load(.series)
        expect(search.series.results.count == 2 && search.series.page == 2, "retry requests same failed page")
        let cancelled = Task { await search.search(query: "cancelled", language: "en-US", type: "all") }
        cancelled.cancel(); await cancelled.value
        expect(search.movies.results.isEmpty && search.series.results.isEmpty, "cancelled search publishes nothing")
        await search.search(query: "pagecancel", language: "en-US", type: "movie")
        let cancelledPage = Task { await search.load(.movie) }
        try await Task.sleep(for: .milliseconds(10))
        cancelledPage.cancel(); await cancelledPage.value
        expect(!search.movies.loading && search.movies.error == nil && search.movies.page == 1, "cancelled pagination preserves results and clears loading")
        let art = RemoteArtworkModel()
        let oldImage = Task { await art.load(path: "/old", role: "poster", pixels: 100, service: fake, images: OutOfOrderImages()) }
        try await Task.sleep(for: .milliseconds(10))
        await art.load(path: "/new", role: "poster", pixels: 100, service: fake, images: OutOfOrderImages())
        await oldImage.value
        expect(art.data == Data("/new".utf8), "obsolete image cannot replace current selection")
        let loader = TMDbImportLoader(service: fake, images: FailingImages())
        let noPoster = try await loader.load(source)
        expect(noPoster.poster == nil && noPoster.metadata.overview == "Overview" && !noPoster.warnings.isEmpty, "poster failure allows text draft")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = MediaRepository(directory: directory)
        let item = MediaItem(title: "manual", status: .watched)
        try await repo.upsert(item)
        try FileManager.default.removeItem(at: directory)
        try Data([1]).write(to: directory)
        var edited = item; edited.title = "changed"
        do { try await repo.upsert(edited); expect(false, "expected disk failure") }
        catch { expect(repo.items.first?.title == "manual", "failed save preserves original library") }
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let corruptURL = directory.appendingPathComponent(LibraryFiles.libraryFileName)
        let corruptBytes = Data("unreadable original".utf8)
        try corruptBytes.write(to: corruptURL)
        let corrupt = MediaRepository(directory: directory)
        await corrupt.waitUntilLoaded()
        let preservedBytes = try Data(contentsOf: corruptURL)
        expect(corrupt.lastError != nil && preservedBytes == corruptBytes, "unreadable library is never overwritten on load")
        do { try await corrupt.upsert(item); expect(false, "expected unreadable save refusal") }
        catch { let bytes = try Data(contentsOf: corruptURL); expect(bytes == corruptBytes, "ordinary save refuses to replace unreadable library") }
        try await corrupt.makeImportBackup()
        try await corrupt.applyImport(LibrarySnapshot(items: [item]), replacingUnreadable: true)
        expect(corrupt.items[0].title == "manual", "explicit backup restore can recover unreadable library")
        let previewRepo = MediaRepository(seedItems: [noPoster.merging(into: item, fields: [.overview])])
        expect(previewRepo.duplicate(for: source) != nil, "repository detects source duplicate")
        do { var duplicate = previewRepo.items[0]; duplicate.id = UUID(); try await previewRepo.upsert(duplicate); expect(false, "expected duplicate") }
        catch { expect(error as? RepositoryError == .duplicate, "duplicate rejected at commit") }
        // Repository transactions, publication, and main-actor reentrancy.
        let transactionFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: transactionFolder) }
        let transactions = MediaRepository(directory: transactionFolder)
        await transactions.waitUntilLoaded()
        let entryOne = MediaItem(title: "entryOne", status: .watched, watchedAt: YearMonth(year: 2024, month: 3), rating: 9)
        let entryTwo = MediaItem(title: "entryTwo", status: .watched, watchedAt: YearMonth(year: 2024, month: 3), rating: 9)
        async let saveFirst: Void = transactions.upsert(entryOne)
        async let saveSecond: Void = transactions.upsert(entryTwo)
        _ = try await (saveFirst, saveSecond)
        expect(transactions.items.count == 2 && transactions.document.revision == 2, "concurrent saves serialize without losing entries")
        expect(transactions.items.allSatisfy { $0.poster == nil && $0.backdrop == nil && $0.logo == nil }, "published list has no attachment payload")
        let creation = transactions.items.first { $0.id == entryOne.id }!.createdAt
        let modified = transactions.items.first { $0.id == entryOne.id }!.updatedAt
        let homeIDs = transactions.homeOrder
        try await transactions.applyHomeReorder(Array(homeIDs.reversed()))
        expect(transactions.document.revision == 3 && transactions.items.first { $0.id == entryOne.id }!.updatedAt == modified, "reorder advances document revision without changing content timestamps")
        var edit = entryOne; edit.title = "edited"; edit.createdAt = .distantPast; edit.updatedAt = .distantPast
        try await transactions.upsert(edit)
        expect(transactions.items.first { $0.id == entryOne.id }!.createdAt == creation, "repository owns creation timestamp")
        expect(transactions.items.first { $0.id == entryOne.id }!.updatedAt >= modified, "repository owns modification timestamp")
        let beforeInvalid = transactions.document.revision
        edit.rating = 11
        do { try await transactions.upsert(edit); expect(false, "invalid rating should fail") }
        catch { expect(transactions.document.revision == beforeInvalid && transactions.items.first { $0.id == entryOne.id }!.rating == 9, "invalid candidate leaves revision and published state unchanged") }
        do { try await transactions.applyHomeReorder([entryOne.id, entryOne.id]); expect(false, "duplicate reorder should fail") }
        catch { expect(transactions.document.revision == beforeInvalid, "invalid repository reorder leaves revision unchanged") }
        var remote = LibraryDocument(items: [entryTwo]); remote.revision = 20
        try await transactions.applyImport(remote, backup: true)
        expect(transactions.document.libraryID == remote.libraryID && transactions.document.revision == 21, "whole-library import adopts library identity and advances revision")
        let backedUp = try LibraryArchive.read(from: transactionFolder.appendingPathComponent("导入前完整备份"))
        expect(backedUp.items.count == 2 && backedUp.revision == beforeInvalid, "import backup is the immediately preceding document")
        let diskFile = transactionFolder.appendingPathComponent(LibraryFiles.libraryFileName)
        let unknown = Data("{\"schemaVersion\":999}".utf8)
        try unknown.write(to: diskFile)
        do { try await transactions.upsert(entryTwo); expect(false, "externally replaced file should fail") }
        catch {
            let preserved = try Data(contentsOf: diskFile)
            expect(preserved == unknown && transactions.document.revision == 21, "external unsupported file is preserved and not overwritten")
        }
        // No real credentials or Keychain access: exercise provisioning and transactional settings.
        let suite = "SakuraReel.settings-tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        var storedKey = ""
        let settings = TMDbSettings(preferences: preferences, readKey: { "" }, persistKey: { storedKey = $0 })
        expect(!settings.hasKey, "missing key requires onboarding")
        let bundleURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).bundle")
        defer { try? FileManager.default.removeItem(at: bundleURL) }
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": "settings.test", "TMDbDefaultAPIKey": "fixture-default"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundleURL.appendingPathComponent("Info.plist"))
        let generation = settings.generation
        try settings.useDefaultKey(bundle: Bundle(url: bundleURL)!)
        expect(settings.hasKey && storedKey == "fixture-default" && settings.connection.key == storedKey,
               "skip provisions default into credential storage and subsequent requests")
        expect(settings.host == "api.themoviedb.org" && settings.generation != generation,
               "skip uses direct connection and invalidates prior requests")
        try settings.save(key: "fixture-relay", proxy: relayHost)
        expect(settings.connection.host == relayHost && settings.connection.fallbackHosts == [backupHost], "AniShelf proxy selection configures its backup")
        try settings.save(key: "fixture-custom", proxy: "owned.example.com")
        expect(settings.connection.fallbackHosts.isEmpty, "custom proxy does not send credentials to built-in relays")
        try settings.save(key: "fixture-direct", proxy: nil)
        expect(settings.connection.host == TMDbRoutes.direct && settings.connection.fallbackHosts.isEmpty, "turning off proxy removes all relay routes")
        struct CredentialWriteFailure: Error {}
        let failedSettings = TMDbSettings(preferences: preferences, readKey: { "old-key" },
                                          persistKey: { _ in throw CredentialWriteFailure() })
        let oldConnection = failedSettings.connection
        do { try failedSettings.save(key: "new-key", proxy: "https://selected.example"); expect(false, "expected credential failure") }
        catch { expect(failedSettings.connection.key == oldConnection.key && failedSettings.connection.generation == oldConnection.generation,
                       "credential failure preserves current configuration") }
        print("TMDb service tests passed (\(checks) checks)")
    }
}
