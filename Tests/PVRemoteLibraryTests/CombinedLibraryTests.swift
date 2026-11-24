import PVSystems
import Testing
@testable import PVRemoteLibrary

@Suite struct CombinedLibraryTests {
    private func row(_ rows: [CombinedGame], _ title: String) -> CombinedGame? {
        rows.first { $0.title == title }
    }

    @Test func availabilityFollowsWhereTheGameIs() {
        let local = [
            LocalGameRef(id: "A", title: "Alpha", system: .SNES, md5: "a1"),
            LocalGameRef(id: "B", title: "Beta", system: .SNES, md5: "b1"),
            LocalGameRef(id: "C", title: "Cloud", system: .SNES, md5: "c1", isOnDisk: false),
            LocalGameRef(id: "D", title: "Dropped", system: .SNES, md5: "d1", isOnDisk: false)
        ]
        let online = SourceCatalogue(source: serverA, games: [remote("b", md5: "b1"), remote("c", md5: "c1"), remote("z", title: "Zeta")], isReachable: true)
        let offline = SourceCatalogue(source: serverB, games: [remote("d", on: serverB, md5: "d1"), remote("o", on: serverB, title: "Omega")], isReachable: false)
        let rows = CombinedLibrary.merge(local: local, catalogues: [online, offline])

        #expect(rows.count == 6)
        #expect(row(rows, "Alpha")?.availability == .onDevice)
        #expect(row(rows, "Beta")?.availability == .onDeviceAndSources)
        #expect(row(rows, "Cloud")?.availability == .localRecordOnly)
        #expect(row(rows, "Dropped")?.availability == .missingFile)
        #expect(row(rows, "Zeta")?.availability == .remoteOnly)
        #expect(row(rows, "Omega")?.availability == .unreachable)
        #expect(rows.map(\.title) == ["Alpha", "Beta", "Cloud", "Dropped", "Omega", "Zeta"])
    }

    @Test func theSameGameOnTwoSourcesIsOneRow() {
        let first = SourceCatalogue(source: serverA, games: [remote("1", title: "Game", md5: "ff")], isReachable: false)
        let second = SourceCatalogue(source: serverB, games: [remote("9", on: serverB, title: "Game", md5: "ff")], isReachable: true)
        let rows = CombinedLibrary.merge(local: [], catalogues: [first, second])
        #expect(rows.count == 1)
        #expect(rows[0].sources == [serverA, serverB])
        #expect(rows[0].availability == .remoteOnly, "one reachable source is enough")
    }

    @Test func oneSourceListingTwoAlikeGamesKeepsBoth() {
        let games = [remote("1", file: "game.sfc"), remote("2", file: "game.sfc")]
        let rows = CombinedLibrary.merge(local: [], catalogues: [SourceCatalogue(source: serverA, games: games, isReachable: true)])
        #expect(rows.count == 2)
    }

    @Test func aTransferShowsOnItsRow() {
        let game = remote("z", title: "Zeta")
        let rows = CombinedLibrary.merge(
            local: [], catalogues: [SourceCatalogue(source: serverA, games: [game], isReachable: true)],
            transfers: [game.id: .downloading(0.5)]
        )
        #expect(rows[0].transfer == .downloading(0.5))
    }

    @Test func sectionsGroupBySystemWithUnmappedLast() {
        let games = [remote("n", title: "N", system: .NES), remote("s", title: "S"), remote("u", title: "U", system: nil)]
        let rows = CombinedLibrary.merge(local: [], catalogues: [SourceCatalogue(source: serverA, games: games, isReachable: true)])
        let sections = CombinedLibrary.sections(rows)
        #expect(sections.count == 3)
        #expect(sections.last?.system == nil)
        #expect(Set(sections.dropLast().compactMap(\.system)) == [.NES, .SNES])
    }

    @Test func searchFiltersByTitle() {
        let rows = CombinedLibrary.merge(local: [
            LocalGameRef(id: "A", title: "Alpha", system: .SNES), LocalGameRef(id: "B", title: "Beta", system: .SNES)
        ], catalogues: [])
        #expect(CombinedLibrary.filter(rows, search: " alp ").map(\.title) == ["Alpha"])
        #expect(CombinedLibrary.filter(rows, search: "").count == 2)
    }
}
