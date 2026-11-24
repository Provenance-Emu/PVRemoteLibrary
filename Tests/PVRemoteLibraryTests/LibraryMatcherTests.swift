import PVSystems
import Testing
@testable import PVRemoteLibrary

@Suite struct LibraryMatcherTests {
    @Test func md5MatchesOnTheSameSystemIgnoringCase() {
        let local = LocalGameRef(id: "L1", title: "Game", system: .SNES, md5: "ABCDEF", sizeBytes: 100)
        let matcher = LibraryMatcher(local: [local])
        #expect(matcher.localMatch(for: remote("r", md5: "abcdef", size: 100))?.id == "L1")
        #expect(matcher.localMatch(for: remote("r", md5: "abcdef")) != nil, "unknown size still matches")
        #expect(matcher.localMatch(for: remote("r", system: .NES, md5: "abcdef")) == nil)
        #expect(matcher.localMatch(for: remote("r", md5: "abcdef", size: 99)) == nil)
    }

    @Test func discSetsNeverMatchByMD5() {
        let local = LocalGameRef(id: "L1", title: "Disc", system: .PSX, md5: "aa", isSingleFileImage: false)
        #expect(LibraryMatcher(local: [local]).localMatch(for: remote("r", system: .PSX, md5: "aa")) == nil)
    }

    @Test func aRecordedLinkMatchesWhenNothingElseDoes() {
        let local = LocalGameRef(id: "L1", title: "Renamed", system: .SNES, md5: "11")
        let game = remote("r", md5: "22", file: "other.sfc")
        #expect(LibraryMatcher(local: [local], links: [game.id: "L1"]).localMatch(for: game)?.id == "L1")
        #expect(LibraryMatcher(local: [local], links: [game.id: "gone"]).localMatch(for: game) == nil)
    }

    @Test func gameIDNeedsTheSameDiscNumber() {
        let disc1 = LocalGameRef(id: "D1", title: "Disc 1", system: .GameCube, gameID: "GM4E01", discNumber: 1)
        let matcher = LibraryMatcher(local: [disc1])
        #expect(matcher.localMatch(for: remote("r", system: .GameCube, gameID: "gm4e01", disc: 1))?.id == "D1")
        #expect(matcher.localMatch(for: remote("r", system: .GameCube, gameID: "GM4E01", disc: 2)) == nil)
        #expect(matcher.localMatch(for: remote("r", system: .GameCube, gameID: "GM4E01")) == nil, "no disc number is not disc 1")
    }

    @Test func fileNameMatchesIgnoringCaseAndFolders() {
        let local = LocalGameRef(id: "L1", title: "Game", system: .SNES, fileName: "Super Game (USA).sfc")
        let matcher = LibraryMatcher(local: [local])
        #expect(matcher.localMatch(for: remote("r", file: "roms/super game (usa).SFC"))?.id == "L1")
        #expect(matcher.localMatch(for: remote("r", file: "Super Game (USA).zip")) == nil)
        #expect(matcher.localMatch(for: remote("r", title: "Game")) == nil, "titles never match")
    }

    @Test func linksSurviveASaveAndLoad() throws {
        let store = SourceLinkStore(file: temporaryDirectory().appendingPathComponent("nested/links.json"))
        #expect(store.load().isEmpty)
        try store.save(["a": "b"])
        #expect(store.load() == ["a": "b"])
    }
}
