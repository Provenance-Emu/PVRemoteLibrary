import Foundation
import Testing
@testable import PVRemoteLibrary

@Suite struct CacheTests {
    @Test func aCatalogueSurvivesSaveLoadAndRemove() async throws {
        let store = RemoteCatalogueStore(directory: temporaryDirectory())
        let source = LibrarySourceID(rawValue: "ecs:https://host:8473/a b")
        #expect(await store.load(source) == nil)
        let catalogue = CachedCatalogue(source: source, games: [remote("1", on: source, md5: "AB")], fetched: Date(timeIntervalSince1970: 1000), isComplete: false)
        try await store.save(catalogue)
        #expect(await store.load(source) == catalogue)
        await store.remove(source)
        #expect(await store.load(source) == nil)
    }

    @Test func aCatalogueGoesStaleAfterTenMinutes() {
        let catalogue = CachedCatalogue(source: serverA, games: [], fetched: Date(timeIntervalSince1970: 0), isComplete: true)
        #expect(!catalogue.isStale(now: Date(timeIntervalSince1970: 600)))
        #expect(catalogue.isStale(now: Date(timeIntervalSince1970: 601)))
    }

    @Test func coversAreRevalidatedWithTheStoredETag() async {
        let cache = RemoteCoverCache(directory: temporaryDirectory())
        let source = FakeSource(pages: [])
        let game = remote("1", art: true)
        let bytes = Data("not an image, kept as sent".utf8)

        await source.setCover(.image(bytes, etag: "v1"))
        #expect(await cache.cover(for: game, from: source) == bytes)

        await source.setCover(.notModified)
        #expect(await cache.cover(for: game, from: source) == bytes)
        #expect(await source.etagsSeen == [nil, "v1"])

        await source.setFails(true)
        #expect(await cache.cover(for: game, from: source) == bytes, "offline falls back to disk")

        await cache.removeAll(for: game.source)
        #expect(await cache.cached(for: game) == nil)
    }

    @Test func aGameWithoutArtNeverAsksTheSource() async {
        let source = FakeSource(pages: [])
        #expect(await RemoteCoverCache(directory: temporaryDirectory()).cover(for: remote("1"), from: source) == nil)
        #expect(await source.etagsSeen.isEmpty)
    }
}
