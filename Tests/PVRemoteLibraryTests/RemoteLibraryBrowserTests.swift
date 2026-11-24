import Foundation
import PVSystems
import Testing
@testable import PVRemoteLibrary

@MainActor
@Suite struct RemoteLibraryBrowserTests {
    final class Library: @unchecked Sendable {
        var games: [LocalGameRef] = []
        var imported: [String] = []
    }

    private func browser(_ library: Library, cache: URL = temporaryDirectory(), now: Date = Date()) -> RemoteLibraryBrowser {
        RemoteLibraryBrowser(
            cacheDirectory: cache, downloadDirectory: temporaryDirectory(),
            hooks: .init(
                localGames: { library.games },
                importGame: { _, game in
                    library.imported.append(game.id)
                    library.games.append(LocalGameRef(id: "new", title: game.title, system: .SNES))
                    return "new"
                }
            ),
            now: { now }
        )
    }

    @Test func openingLoadsThenPagesWithoutDuplicates() async {
        let source = FakeSource(pages: [[remote("1"), remote("2")], [remote("2"), remote("3")]])
        let browser = browser(Library())
        browser.add(source)
        await browser.open(serverA)
        #expect(browser.sources[0].phase == .loaded)
        #expect(browser.sources[0].hasMore)
        await browser.loadMore(serverA)
        #expect(browser.rows.map(\.title) == ["1", "2", "3"])
        #expect(!browser.sources[0].hasMore)
    }

    @Test func aSecondLaunchShowsTheCacheAndSkipsAFreshRefetch() async {
        let cache = temporaryDirectory()
        let first = browser(Library(), cache: cache)
        first.add(FakeSource(pages: [[remote("1")]]))
        await first.open(serverA)

        let source = FakeSource(pages: [[remote("1"), remote("2")]])
        let second = browser(Library(), cache: cache)
        second.add(source)
        await second.open(serverA)
        #expect(second.rows.map(\.title) == ["1"])
        #expect(second.sources[0].isStale)
        #expect(await source.pageCalls == 0)

        await second.open(serverA, force: true)
        #expect(second.rows.map(\.title) == ["1", "2"])
        #expect(!second.sources[0].isStale)
    }

    @Test func anOldCacheIsShownThenRefreshed() async {
        let cache = temporaryDirectory()
        let first = browser(Library(), cache: cache, now: Date(timeIntervalSince1970: 0))
        first.add(FakeSource(pages: [[remote("1")]]))
        await first.open(serverA)

        let source = FakeSource(pages: [[remote("2")]])
        let second = browser(Library(), cache: cache, now: Date(timeIntervalSince1970: 3600))
        second.add(source)
        await second.open(serverA)
        #expect(await source.pageCalls == 1)
        #expect(second.rows.map(\.title) == ["2"])
    }

    @Test func aFailedRefreshKeepsTheGamesAndMarksThemUnreachable() async {
        let source = FakeSource(pages: [[remote("1")]])
        let browser = browser(Library())
        browser.add(source)
        await browser.open(serverA)
        await source.setFails(true)
        await browser.refresh(serverA)
        #expect(browser.sources[0].phase == .failed("offline"))
        #expect(browser.rows.map(\.availability) == [.unreachable])
    }

    @Test func scopesChooseWhatIsListed() async {
        let library = Library()
        library.games = [LocalGameRef(id: "L", title: "Local", system: .SNES), LocalGameRef(id: "S", title: "Shared", system: .SNES, md5: "aa")]
        let browser = browser(library)
        browser.add(FakeSource(pages: [[remote("s", title: "Shared", md5: "aa"), remote("r", title: "Remote")]]))
        await browser.open(serverA)

        #expect(browser.rows.map(\.title) == ["Local", "Remote", "Shared"])
        browser.scope = .local
        #expect(browser.rows.map(\.title) == ["Local", "Shared"])
        #expect(browser.rows.allSatisfy { $0.availability == .onDevice })
        browser.scope = .source(serverA)
        #expect(browser.rows.map(\.title) == ["Remote", "Shared"])
        #expect(browser.rows.map(\.availability) == [.remoteOnly, .onDeviceAndSources])
        browser.searchText = "rem"
        #expect(browser.rows.map(\.title) == ["Remote"])
    }

    @Test func serverSearchAddsGamesNeverBrowsed() async throws {
        let source = FakeSource(pages: [[remote("1", title: "Mario")]], capabilities: [.paging, .serverSearch])
        await source.setSearchHits([remote("7", title: "Mario Kart")])
        let browser = browser(Library())
        browser.add(source)
        await browser.open(serverA)
        browser.searchText = "mario"
        browser.searchSources()
        for _ in 0..<200 where browser.rows.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(browser.rows.map(\.title) == ["Mario", "Mario Kart"])
    }

    @Test func downloadingImportsAndLinksTheGame() async throws {
        let library = Library()
        let cache = temporaryDirectory()
        let browser = browser(library, cache: cache)
        let game = remote("1", title: "Zeta", file: "zeta.sfc")
        browser.add(FakeSource(pages: [[game]]))
        await browser.open(serverA)
        browser.download(browser.rows[0])
        for _ in 0..<200 where library.imported.isEmpty || !browser.transfers.isEmpty { try await Task.sleep(for: .milliseconds(10)) }

        #expect(library.imported == [game.id])
        #expect(browser.transfers.isEmpty)
        #expect(browser.rows.count == 1, "the imported copy and the server's entry are one row")
        #expect(browser.rows[0].local?.id == "new")
        #expect(browser.rows[0].availability == .onDeviceAndSources)
        #expect(SourceLinkStore(file: cache.appendingPathComponent("links.json")).load() == [game.id: "new"])
    }

    @Test func aFailedDownloadIsReportedOnTheRow() async throws {
        let source = FakeSource(pages: [[remote("1")]])
        let browser = browser(Library())
        browser.add(source)
        await browser.open(serverA)
        await source.setFails(true)
        browser.download(browser.rows[0])
        for _ in 0..<200 where browser.rows[0].transfer != .failed("offline") { try await Task.sleep(for: .milliseconds(10)) }
        #expect(browser.rows[0].transfer == .failed("offline"))
    }

    @Test func removingASourceForgetsItsGamesAndCache() async {
        let cache = temporaryDirectory()
        let browser = browser(Library(), cache: cache)
        browser.add(FakeSource(pages: [[remote("1")]]))
        await browser.open(serverA)
        browser.scope = .source(serverA)
        await browser.remove(serverA)
        #expect(browser.rows.isEmpty)
        #expect(browser.scope == .combined)
        #expect(await RemoteCatalogueStore(directory: cache.appendingPathComponent("Catalogues")).load(serverA) == nil)
    }
}
