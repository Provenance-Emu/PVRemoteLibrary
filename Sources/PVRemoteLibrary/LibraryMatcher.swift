import Foundation
import PVSystems

/// Decides whether a source's game is one the library already lists.
///
/// Rules, strongest first. Titles are never compared.
/// 1. Same system, same MD5, and the same size when both sides know it.
/// 2. A recorded link: the local game was downloaded from that entry.
/// 3. Same system, same game id and same disc number.
/// 4. Same system and same file name, ignoring case.
public struct LibraryMatcher: Sendable {
    struct HashKey: Hashable {
        let system: SystemIdentifier
        let md5: String
    }

    struct DiscKey: Hashable {
        let system: SystemIdentifier
        let gameID: String
        let discNumber: Int?
    }

    struct NameKey: Hashable {
        let system: SystemIdentifier
        let name: String
    }

    private var byHash: [HashKey: [LocalGameRef]] = [:]
    private var byDisc: [DiscKey: LocalGameRef] = [:]
    private var byName: [NameKey: LocalGameRef] = [:]
    private var byID: [String: LocalGameRef] = [:]
    private let links: [String: String]

    /// - Parameter links: `LibraryGame.id` to `LocalGameRef.id`, from `SourceLinkStore`.
    public init(local: [LocalGameRef], links: [String: String] = [:]) {
        self.links = links
        for game in local {
            byID[game.id] = game
            if game.isSingleFileImage, let md5 = game.md5, !md5.isEmpty {
                byHash[HashKey(system: game.system, md5: md5), default: []].append(game)
            }
            if let key = Self.discKey(system: game.system, gameID: game.gameID, discNumber: game.discNumber) {
                byDisc[key] = byDisc[key] ?? game
            }
            if let key = Self.nameKey(system: game.system, fileName: game.fileName) {
                byName[key] = byName[key] ?? game
            }
        }
    }

    /// The local game `remote` is a copy of, or nil.
    public func localMatch(for remote: LibraryGame) -> LocalGameRef? {
        guard let system = remote.system else {
            return links[remote.id].flatMap { byID[$0] }
        }
        if let md5 = remote.md5, !md5.isEmpty,
           let found = byHash[HashKey(system: system, md5: md5)]?.first(where: {
               $0.sizeBytes == 0 || remote.sizeBytes == 0 || $0.sizeBytes == remote.sizeBytes
           }) {
            return found
        }
        if let linked = links[remote.id].flatMap({ byID[$0] }) { return linked }
        if let key = Self.discKey(system: system, gameID: remote.gameID, discNumber: remote.discNumber), let found = byDisc[key] {
            return found
        }
        if let key = Self.nameKey(system: system, fileName: remote.fileName), let found = byName[key] {
            return found
        }
        return nil
    }

    /// Keys under which two sources' entries count as the same game, strongest first.
    static func remoteKeys(for game: LibraryGame) -> [AnyHashable] {
        guard let system = game.system else { return [] }
        var keys: [AnyHashable] = []
        if let md5 = game.md5, !md5.isEmpty { keys.append(HashKey(system: system, md5: md5)) }
        if let key = discKey(system: system, gameID: game.gameID, discNumber: game.discNumber) { keys.append(key) }
        if let key = nameKey(system: system, fileName: game.fileName) { keys.append(key) }
        return keys
    }

    private static func discKey(system: SystemIdentifier, gameID: String?, discNumber: Int?) -> DiscKey? {
        guard let gameID, !gameID.isEmpty else { return nil }
        return DiscKey(system: system, gameID: gameID.uppercased(), discNumber: discNumber)
    }

    private static func nameKey(system: SystemIdentifier, fileName: String?) -> NameKey? {
        guard let name = fileName.map({ ($0 as NSString).lastPathComponent }), !name.isEmpty else { return nil }
        return NameKey(system: system, name: name.precomposedStringWithCanonicalMapping.lowercased())
    }
}

/// Remembers which local game came from which source entry, so the two stay
/// one row after the importer has renamed or re-hashed the file.
public struct SourceLinkStore: Sendable {
    private let file: URL

    public init(file: URL) { self.file = file }

    /// `LibraryGame.id` to `LocalGameRef.id`. Empty when nothing was saved or the file is unreadable.
    public func load() -> [String: String] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    public func save(_ links: [String: String]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(links).write(to: file, options: .atomic)
    }
}
