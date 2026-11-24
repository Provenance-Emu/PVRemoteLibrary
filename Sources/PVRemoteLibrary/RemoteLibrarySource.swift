import Foundation
import PVSystems

public struct SourceCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// `page` honours `CatalogueQuery.search`; otherwise the browser filters what it has.
    public static let serverSearch = SourceCapabilities(rawValue: 1 << 0)
    /// The catalogue arrives in pages; otherwise `page` returns everything at once.
    public static let paging = SourceCapabilities(rawValue: 1 << 1)
    /// A fetched game may be played without being kept in the library.
    public static let temporaryPlay = SourceCapabilities(rawValue: 1 << 2)
}

public struct CatalogueQuery: Hashable, Sendable {
    public var search: String
    /// Limits the answer to these systems when the source can; nil asks for all.
    public var systems: Set<SystemIdentifier>?

    public init(search: String = "", systems: Set<SystemIdentifier>? = nil) {
        self.search = search
        self.systems = systems
    }
}

/// Where a source's next page starts. Only the source that made it reads it.
public struct CatalogueCursor: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct CataloguePage: Sendable {
    public var games: [LibraryGame]
    /// nil on the last page.
    public var next: CatalogueCursor?

    public init(games: [LibraryGame], next: CatalogueCursor? = nil) {
        self.games = games
        self.next = next
    }
}

public enum ArtworkResult: Sendable, Equatable {
    /// The source has no cover for the game.
    case none
    /// The cover still matches the ETag that was sent.
    case notModified
    case image(Data, etag: String?)
}

public enum FetchProgress: Sendable, Equatable {
    case preparing
    /// 0...1 across every file of the game.
    case downloading(Double)
    case verifying
}

/// A game's files on this device, ready for the app's importer.
public struct FetchedGame: Sendable, Equatable {
    /// The folder holding `files`. The caller deletes it when done.
    public var directory: URL
    public var files: [URL]

    public init(directory: URL, files: [URL]) {
        self.directory = directory
        self.files = files
    }
}

/// A server, share or peer that lists games and hands over their files.
///
/// The source owns its own transfer: ranged requests, resume, verification and
/// background sessions differ too much between servers to share one shape.
public protocol RemoteLibrarySource: Actor {
    nonisolated var info: LibrarySourceInfo { get }
    nonisolated var capabilities: SourceCapabilities { get }

    /// One page of the catalogue. A nil cursor starts from the beginning.
    func page(_ query: CatalogueQuery, after cursor: CatalogueCursor?) async throws -> CataloguePage

    /// The game's cover. `etag` is what the caller already holds, if anything.
    func artwork(for game: LibraryGame, etag: String?) async throws -> ArtworkResult

    /// Downloads every file of `game` into a new folder under `directory`.
    func fetch(
        _ game: LibraryGame, into directory: URL, progress: @escaping @Sendable (FetchProgress) -> Void
    ) async throws -> FetchedGame
}
