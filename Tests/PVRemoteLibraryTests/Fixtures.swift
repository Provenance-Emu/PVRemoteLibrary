import Foundation
import PVSystems
@testable import PVRemoteLibrary

let serverA = LibrarySourceID(rawValue: "ecs:a")
let serverB = LibrarySourceID(rawValue: "romm:b")

func remote(
    _ id: String, on source: LibrarySourceID = serverA, title: String? = nil, system: SystemIdentifier? = .SNES,
    md5: String? = nil, size: Int64 = 0, file: String? = nil, gameID: String? = nil, disc: Int? = nil, art: Bool = false
) -> LibraryGame {
    LibraryGame(
        source: source, sourceGameID: id, title: title ?? id, system: system, platformName: "snes",
        md5: md5, sizeBytes: size, fileName: file, artKey: art ? id : nil, gameID: gameID, discNumber: disc
    )
}

func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pvrl-" + UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

struct FakeError: Error, LocalizedError {
    var errorDescription: String? { "offline" }
}

/// A source whose pages, covers and failures the test sets.
actor FakeSource: RemoteLibrarySource {
    nonisolated let info: LibrarySourceInfo
    nonisolated let capabilities: SourceCapabilities
    var pages: [[LibraryGame]]
    var searchHits: [LibraryGame] = []
    var fails = false
    var cover: ArtworkResult = .none
    private(set) var pageCalls = 0
    private(set) var etagsSeen: [String?] = []

    init(_ id: LibrarySourceID = serverA, pages: [[LibraryGame]], capabilities: SourceCapabilities = [.paging]) {
        info = LibrarySourceInfo(id: id, kind: .contentServer, name: "server", symbol: "server.rack")
        self.pages = pages
        self.capabilities = capabilities
    }

    func setFails(_ value: Bool) { fails = value }
    func setCover(_ value: ArtworkResult) { cover = value }
    func setSearchHits(_ value: [LibraryGame]) { searchHits = value }

    func page(_ query: CatalogueQuery, after cursor: CatalogueCursor?) async throws -> CataloguePage {
        pageCalls += 1
        if fails { throw FakeError() }
        if !query.search.isEmpty { return CataloguePage(games: searchHits) }
        let index = cursor.flatMap { Int($0.rawValue) } ?? 0
        guard index < pages.count else { return CataloguePage(games: []) }
        return CataloguePage(games: pages[index], next: index + 1 < pages.count ? CatalogueCursor(String(index + 1)) : nil)
    }

    func artwork(for game: LibraryGame, etag: String?) async throws -> ArtworkResult {
        etagsSeen.append(etag)
        if fails { throw FakeError() }
        return cover
    }

    func fetch(
        _ game: LibraryGame, into directory: URL, progress: @escaping @Sendable (FetchProgress) -> Void
    ) async throws -> FetchedGame {
        if fails { throw FakeError() }
        progress(.downloading(1))
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(game.fileName ?? "game.bin")
        try Data("rom".utf8).write(to: file)
        return FetchedGame(directory: folder, files: [file])
    }
}
