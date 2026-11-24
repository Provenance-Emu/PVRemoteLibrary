import CryptoKit
import Foundation

/// A source's catalogue as last seen, kept so a library opens without the network.
public struct CachedCatalogue: Codable, Sendable, Equatable {
    public var source: LibrarySourceID
    public var games: [LibraryGame]
    public var fetched: Date
    /// False while a paged source has more pages that were never loaded.
    public var isComplete: Bool

    public init(source: LibrarySourceID, games: [LibraryGame], fetched: Date, isComplete: Bool) {
        self.source = source
        self.games = games
        self.fetched = fetched
        self.isComplete = isComplete
    }

    public func isStale(now: Date = Date(), maxAge: TimeInterval = RemoteCatalogueStore.defaultMaxAge) -> Bool {
        now.timeIntervalSince(fetched) > maxAge
    }
}

/// One JSON file per source, in a folder the app chooses (normally under Caches).
public actor RemoteCatalogueStore {
    public static let defaultMaxAge: TimeInterval = 600

    private let directory: URL

    public init(directory: URL) { self.directory = directory }

    /// nil when nothing was saved, or the file cannot be read.
    public func load(_ source: LibrarySourceID) -> CachedCatalogue? {
        guard let data = try? Data(contentsOf: file(for: source)) else { return nil }
        return try? JSONDecoder().decode(CachedCatalogue.self, from: data)
    }

    public func save(_ catalogue: CachedCatalogue) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(catalogue).write(to: file(for: catalogue.source), options: .atomic)
    }

    public func remove(_ source: LibrarySourceID) {
        try? FileManager.default.removeItem(at: file(for: source))
    }

    private func file(for source: LibrarySourceID) -> URL {
        directory.appendingPathComponent(CacheFileName.hashed(source.rawValue) + ".json")
    }
}

enum CacheFileName {
    /// Source and game ids hold URLs and slashes; a digest is always a safe file name.
    static func hashed(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
