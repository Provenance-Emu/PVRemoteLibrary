import Foundation
import Observation
import PVSystems

/// What a library screen reads to show local games, one source, or everything at once.
///
/// The app supplies its local games and its importer; the browser owns the
/// sources, their cached catalogues, matching and transfers. It draws nothing.
@MainActor
@Observable
public final class RemoteLibraryBrowser {
    public enum Scope: Hashable, Sendable {
        /// Local games and every source, each game once.
        case combined
        case local
        case source(LibrarySourceID)
    }

    public enum Phase: Equatable, Sendable {
        case idle
        case loading
        case loaded
        /// The last refresh failed. Games already listed stay listed.
        case failed(String)
    }

    public struct SourceState: Sendable, Identifiable {
        public var info: LibrarySourceInfo
        public var games: [LibraryGame] = []
        public var phase: Phase = .idle
        /// True while the games shown come from the cache and no refresh has finished.
        public var isStale = false
        public var hasMore = false
        public var isReachable = true
        public var id: LibrarySourceID { info.id }
    }

    /// The app's side of the browser.
    public struct Hooks: Sendable {
        /// The library on this device, as it is now.
        public var localGames: @MainActor @Sendable () -> [LocalGameRef]
        /// Imports a fetched game. Returns the new local game's id when it is
        /// known at once, so the two are linked; nil when the import is queued.
        public var importGame: @MainActor @Sendable (FetchedGame, LibraryGame) async throws -> String?

        public init(
            localGames: @escaping @MainActor @Sendable () -> [LocalGameRef],
            importGame: @escaping @MainActor @Sendable (FetchedGame, LibraryGame) async throws -> String?
        ) {
            self.localGames = localGames
            self.importGame = importGame
        }
    }

    public private(set) var sources: [SourceState] = []
    public private(set) var rows: [CombinedGame] = []
    /// By `LibraryGame.id`.
    public private(set) var transfers: [String: TransferState] = [:]
    public var scope: Scope = .combined { didSet { if scope != oldValue { rebuild() } } }
    public var searchText = "" { didSet { if searchText != oldValue { rebuild() } } }
    /// Limits every catalogue request to the systems the app can play.
    public var playableSystems: Set<SystemIdentifier>?

    public var sections: [CombinedLibrary.Section] { CombinedLibrary.sections(rows) }

    @ObservationIgnored private var remote: [LibrarySourceID: any RemoteLibrarySource] = [:]
    @ObservationIgnored private var cursors: [LibrarySourceID: CatalogueCursor] = [:]
    @ObservationIgnored private var loads: [LibrarySourceID: UUID] = [:]
    @ObservationIgnored private var searchResults: [LibrarySourceID: [LibraryGame]] = [:]
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var fetches: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var links: [String: String]
    @ObservationIgnored private let hooks: Hooks
    @ObservationIgnored private let store: RemoteCatalogueStore
    @ObservationIgnored private let linkStore: SourceLinkStore
    @ObservationIgnored private let downloads: URL
    @ObservationIgnored private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - cacheDirectory: holds catalogues and links; normally a folder under Caches.
    ///   - downloadDirectory: where sources put files before the app imports them.
    public init(
        cacheDirectory: URL, downloadDirectory: URL, hooks: Hooks, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.hooks = hooks
        self.now = now
        store = RemoteCatalogueStore(directory: cacheDirectory.appendingPathComponent("Catalogues", isDirectory: true))
        linkStore = SourceLinkStore(file: cacheDirectory.appendingPathComponent("links.json"))
        links = linkStore.load()
        downloads = downloadDirectory
        rebuild()
    }

    // MARK: - Sources

    public func add(_ source: any RemoteLibrarySource) {
        let info = source.info
        remote[info.id] = source
        if let index = sources.firstIndex(where: { $0.id == info.id }) {
            sources[index].info = info
        } else {
            sources.append(SourceState(info: info))
        }
    }

    /// Forgets the source, its cached catalogue and its links.
    public func remove(_ id: LibrarySourceID) async {
        remote[id] = nil
        cursors[id] = nil
        loads[id] = nil
        searchResults[id] = nil
        sources.removeAll { $0.id == id }
        let prefix = id.rawValue + "|"
        links = links.filter { !$0.key.hasPrefix(prefix) }
        try? linkStore.save(links)
        await store.remove(id)
        if scope == .source(id) { scope = .combined }
        rebuild()
    }

    /// Shows the cached catalogue at once, then refreshes it when it is old or `force` is set.
    public func open(_ id: LibrarySourceID, force: Bool = false) async {
        guard let index = index(id) else { return }
        var fresh = false
        if sources[index].games.isEmpty, let cached = await store.load(id), let index = self.index(id) {
            sources[index].games = cached.games
            sources[index].isStale = true
            sources[index].hasMore = false
            fresh = !cached.isStale(now: now())
            rebuild()
        } else if sources[index].phase == .loaded {
            fresh = !sources[index].isStale
        }
        if force || !fresh { await refresh(id) }
    }

    /// Reloads the first page. On failure the games already shown stay, marked unreachable.
    public func refresh(_ id: LibrarySourceID) async {
        guard let source = remote[id], let index = index(id) else { return }
        let load = UUID()
        loads[id] = load
        sources[index].phase = .loading
        do {
            let page = try await source.page(CatalogueQuery(systems: playableSystems), after: nil)
            guard loads[id] == load, let index = self.index(id) else { return }
            cursors[id] = page.next
            sources[index].games = page.games
            sources[index].hasMore = page.next != nil
            sources[index].phase = .loaded
            sources[index].isStale = false
            sources[index].isReachable = true
            await persist(id)
        } catch {
            guard loads[id] == load, let index = self.index(id) else { return }
            sources[index].phase = .failed(error.localizedDescription)
            sources[index].isReachable = false
        }
        rebuild()
    }

    /// The next page of a paged source.
    public func loadMore(_ id: LibrarySourceID) async {
        guard let source = remote[id], let cursor = cursors[id], let load = loads[id] else { return }
        do {
            let page = try await source.page(CatalogueQuery(systems: playableSystems), after: cursor)
            guard loads[id] == load, cursors[id] == cursor, let index = index(id) else { return }
            // A cursor that does not move would loop forever.
            cursors[id] = page.next == cursor ? nil : page.next
            let known = Set(sources[index].games.map(\.id))
            sources[index].games += page.games.filter { !known.contains($0.id) }
            sources[index].hasMore = cursors[id] != nil
            await persist(id)
        } catch {
            guard loads[id] == load, let index = index(id) else { return }
            sources[index].phase = .failed(error.localizedDescription)
        }
        rebuild()
    }

    /// Call when the app's library changed, so rows pick up new and removed games.
    public func localLibraryChanged() { rebuild() }

    // MARK: - Search

    /// Asks sources that search on the server for `searchText`. What is cached is
    /// already filtered as the text changes; this adds games never browsed.
    public func searchSources() {
        searchTask?.cancel()
        let term = searchText.trimmingCharacters(in: .whitespaces)
        searchResults = [:]
        guard !term.isEmpty else { return rebuild() }
        let targets = remote.filter { $0.value.capabilities.contains(.serverSearch) && isInScope($0.key) }
        let query = CatalogueQuery(search: term, systems: playableSystems)
        searchTask = Task { [weak self] in
            for (id, source) in targets {
                guard let page = try? await source.page(query, after: nil), !Task.isCancelled else { continue }
                self?.searchResults[id] = page.games
                self?.rebuild()
            }
        }
    }

    // MARK: - Transfers

    /// Downloads the game from the first reachable source that lists it, then imports it.
    public func download(_ row: CombinedGame) {
        let reachable = Set(sources.filter(\.isReachable).map(\.id))
        guard let game = row.remotes.first(where: { reachable.contains($0.source) }),
              let source = remote[game.source], fetches[game.id] == nil else { return }
        setTransfer(.queued, for: game.id)
        let report: @Sendable (FetchProgress) -> Void = { [weak self] progress in
            Task { @MainActor in self?.report(progress, for: game.id) }
        }
        fetches[game.id] = Task { [weak self, downloads, hooks] in
            do {
                let fetched = try await source.fetch(game, into: downloads, progress: report)
                try Task.checkCancellation()
                self?.setTransfer(.importing, for: game.id)
                let localID = try await hooks.importGame(fetched, game)
                self?.finish(game.id, linkedTo: localID)
            } catch is CancellationError {
                self?.finish(game.id, linkedTo: nil)
            } catch {
                self?.fetches[game.id] = nil
                self?.setTransfer(.failed(error.localizedDescription), for: game.id)
            }
        }
    }

    public func cancelDownload(_ row: CombinedGame) {
        for game in row.remotes {
            fetches[game.id]?.cancel()
        }
    }

    /// Records that `localID` is the library's copy of `game`, for imports that finish later.
    public func link(_ game: LibraryGame, toLocal localID: String) {
        links[game.id] = localID
        try? linkStore.save(links)
        rebuild()
    }

    private func report(_ progress: FetchProgress, for id: String) {
        // Progress hops threads; ignore what arrives after the transfer ended.
        guard fetches[id] != nil, transfers[id] != .importing else { return }
        switch progress {
        case .preparing: setTransfer(.queued, for: id)
        case .downloading(let fraction): setTransfer(.downloading(fraction), for: id)
        case .verifying: setTransfer(.verifying, for: id)
        }
    }

    private func finish(_ id: String, linkedTo localID: String?) {
        fetches[id] = nil
        transfers[id] = nil
        if let localID {
            links[id] = localID
            try? linkStore.save(links)
        }
        rebuild()
    }

    private func setTransfer(_ state: TransferState, for id: String) {
        transfers[id] = state
        rebuild()
    }

    // MARK: - Rows

    private func index(_ id: LibrarySourceID) -> Int? {
        sources.firstIndex { $0.id == id }
    }

    private func isInScope(_ id: LibrarySourceID) -> Bool {
        switch scope {
        case .combined: return true
        case .local: return false
        case .source(let selected): return selected == id
        }
    }

    private func persist(_ id: LibrarySourceID) async {
        guard let state = sources.first(where: { $0.id == id }) else { return }
        // The cache only speeds up the next open; a failed write costs one refetch.
        try? await store.save(CachedCatalogue(source: id, games: state.games, fetched: now(), isComplete: !state.hasMore))
    }

    private func rebuild() {
        let local = hooks.localGames()
        let catalogues = sources.filter { isInScope($0.id) }.map { state -> SourceCatalogue in
            var games = state.games
            if let found = searchResults[state.id] {
                let known = Set(games.map(\.id))
                games += found.filter { !known.contains($0.id) }
            }
            return SourceCatalogue(source: state.id, games: games, isReachable: state.isReachable)
        }
        var merged = CombinedLibrary.merge(local: local, catalogues: catalogues, links: links, transfers: transfers)
        if case .source = scope {
            // One source's library: its games only, still marked with what is already on this device.
            merged.removeAll { $0.remotes.isEmpty }
        }
        rows = CombinedLibrary.filter(merged, search: searchText)
    }
}
