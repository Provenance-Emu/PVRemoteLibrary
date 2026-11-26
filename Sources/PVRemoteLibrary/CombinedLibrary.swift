import Foundation
import PVSystems

@frozen public enum Availability: Sendable, Equatable {
    /// The file is on this device and no source lists the game.
    case onDevice
    /// The file is on this device and at least one source lists the game.
    case onDeviceAndSources
    /// In the library without its file; a reachable source can supply it.
    case localRecordOnly
    /// In the library without its file, and no reachable source lists it.
    case missingFile
    /// On a reachable source only.
    case remoteOnly
    /// Known only from the cached catalogue of a source that is offline.
    case unreachable
}

@frozen public enum TransferState: Sendable, Equatable {
    case queued
    /// The download is underway and its completion fraction is unknown.
    case downloadingIndeterminate
    case downloading(Double)
    case verifying
    case importing
    case failed(String)
}

/// One game, wherever it lives.
public struct CombinedGame: Identifiable, Sendable, Equatable {
    /// The local id when there is one, else the first source entry's id.
    public var id: String
    public var local: LocalGameRef?
    /// One entry per source that lists the game.
    public var remotes: [LibraryGame]
    public var availability: Availability
    public var transfer: TransferState?

    public var title: String { local?.title ?? remotes.first?.title ?? "" }
    public var system: SystemIdentifier? { local?.system ?? remotes.first?.system }
    public var sources: [LibrarySourceID] { remotes.map(\.source) }
    public var isPlayableNow: Bool { availability == .onDevice || availability == .onDeviceAndSources }
}

/// What a source has listed, and whether it answers right now.
public struct SourceCatalogue: Sendable {
    public var source: LibrarySourceID
    public var games: [LibraryGame]
    public var isReachable: Bool

    public init(source: LibrarySourceID, games: [LibraryGame], isReachable: Bool) {
        self.source = source
        self.games = games
        self.isReachable = isReachable
    }
}

@frozen public enum CombinedLibrary {
    public struct Section: Identifiable, Sendable, Equatable {
        /// nil holds games whose platform maps to no system.
        public var system: SystemIdentifier?
        public var games: [CombinedGame]
        public var id: String { system?.rawValue ?? "" }
    }

    /// Local games and every catalogue as one list, each game once, sorted by title.
    ///
    /// - Parameter transfers: by `LibraryGame.id`.
    public static func merge(
        local: [LocalGameRef], catalogues: [SourceCatalogue],
        links: [String: String] = [:], transfers: [String: TransferState] = [:]
    ) -> [CombinedGame] {
        let matcher = LibraryMatcher(local: local, links: links)
        let reachable = Set(catalogues.filter(\.isReachable).map(\.source))
        var remotesByLocal: [String: [LibraryGame]] = [:]
        var groups: [[LibraryGame]] = []
        var groupByKey: [AnyHashable: Int] = [:]

        for catalogue in catalogues {
            for game in catalogue.games {
                if let match = matcher.localMatch(for: game) {
                    remotesByLocal[match.id, default: []].append(game)
                    continue
                }
                let keys = LibraryMatcher.remoteKeys(for: game)
                // One source never lists the same game twice, so only join another source's group.
                if let index = keys.lazy.compactMap({ groupByKey[$0] }).first(where: { index in
                    !groups[index].contains { $0.source == game.source }
                }) {
                    groups[index].append(game)
                    for key in keys where groupByKey[key] == nil { groupByKey[key] = index }
                } else {
                    groups.append([game])
                    for key in keys where groupByKey[key] == nil { groupByKey[key] = groups.count - 1 }
                }
            }
        }

        func transfer(_ remotes: [LibraryGame]) -> TransferState? {
            remotes.lazy.compactMap { transfers[$0.id] }.first
        }

        var rows = local.map { game -> CombinedGame in
            let remotes = remotesByLocal[game.id] ?? []
            let anyReachable = remotes.contains { reachable.contains($0.source) }
            let availability: Availability
            if game.isOnDisk {
                availability = remotes.isEmpty ? .onDevice : .onDeviceAndSources
            } else {
                availability = anyReachable ? .localRecordOnly : .missingFile
            }
            return CombinedGame(id: game.id, local: game, remotes: remotes, availability: availability, transfer: transfer(remotes))
        }
        rows += groups.map { remotes in
            CombinedGame(
                id: remotes[0].id, local: nil, remotes: remotes,
                availability: remotes.contains { reachable.contains($0.source) } ? .remoteOnly : .unreachable,
                transfer: transfer(remotes)
            )
        }
        return rows.sorted {
            let order = $0.title.localizedCaseInsensitiveCompare($1.title)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    /// Rows whose title contains `search`; all rows when it is empty.
    public static func filter(_ games: [CombinedGame], search: String) -> [CombinedGame] {
        let term = search.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return games }
        return games.filter { $0.title.localizedCaseInsensitiveContains(term) }
    }

    /// Rows grouped by system in system order, keeping each group's order. Unmapped games come last.
    public static func sections(_ games: [CombinedGame]) -> [Section] {
        let mapped = Dictionary(grouping: games.filter { $0.system != nil }) { $0.system! }
        var result = mapped.keys.sorted().map { Section(system: $0, games: mapped[$0] ?? []) }
        let unmapped = games.filter { $0.system == nil }
        if !unmapped.isEmpty { result.append(Section(system: nil, games: unmapped)) }
        return result
    }
}
