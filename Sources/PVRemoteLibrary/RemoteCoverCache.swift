import Foundation
#if canImport(ImageIO)
import ImageIO
import UniformTypeIdentifiers
#endif

/// Cover thumbnails on disk, revalidated with the source's ETag.
public actor RemoteCoverCache {
    public static let defaultMaxPixelSize = 640

    private struct Entry: Codable {
        var etag: String?
    }

    private let directory: URL
    private let maxPixelSize: Int

    public init(directory: URL, maxPixelSize: Int = RemoteCoverCache.defaultMaxPixelSize) {
        self.directory = directory
        self.maxPixelSize = maxPixelSize
    }

    /// The cover on disk, without asking the source.
    public func cached(for game: LibraryGame) -> Data? {
        try? Data(contentsOf: imageFile(game))
    }

    /// The game's cover: asks the source, sending the stored ETag, and falls back
    /// to the copy on disk when the source cannot be reached.
    public func cover(for game: LibraryGame, from source: any RemoteLibrarySource) async -> Data? {
        guard game.artKey != nil else { return nil }
        let onDisk = cached(for: game)
        let etag = onDisk == nil ? nil : entry(game)?.etag
        let result: ArtworkResult
        do {
            result = try await source.artwork(for: game, etag: etag)
        } catch {
            return onDisk
        }
        switch result {
        case .none:
            return nil
        case .notModified:
            return onDisk
        case .image(let data, let newETag):
            let thumbnail = Self.thumbnail(data, maxPixelSize: maxPixelSize) ?? data
            store(thumbnail, etag: newETag, for: game)
            return thumbnail
        }
    }

    public func removeAll(for source: LibrarySourceID) {
        try? FileManager.default.removeItem(at: folder(source))
    }

    private func store(_ data: Data, etag: String?, for game: LibraryGame) {
        do {
            try FileManager.default.createDirectory(at: folder(game.source), withIntermediateDirectories: true)
            try data.write(to: imageFile(game), options: .atomic)
            try JSONEncoder().encode(Entry(etag: etag)).write(to: entryFile(game), options: .atomic)
        } catch {
            // A cover that cannot be cached is fetched again next time.
            try? FileManager.default.removeItem(at: imageFile(game))
        }
    }

    private func entry(_ game: LibraryGame) -> Entry? {
        (try? Data(contentsOf: entryFile(game))).flatMap { try? JSONDecoder().decode(Entry.self, from: $0) }
    }

    private func folder(_ source: LibrarySourceID) -> URL {
        directory.appendingPathComponent(CacheFileName.hashed(source.rawValue), isDirectory: true)
    }

    private func imageFile(_ game: LibraryGame) -> URL {
        folder(game.source).appendingPathComponent(CacheFileName.hashed(game.id) + ".img")
    }

    private func entryFile(_ game: LibraryGame) -> URL {
        folder(game.source).appendingPathComponent(CacheFileName.hashed(game.id) + ".json")
    }

    /// A JPEG no larger than `maxPixelSize` on its long side; nil when `data` is not an image.
    static func thumbnail(_ data: Data, maxPixelSize: Int) -> Data? {
        #if canImport(ImageIO)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        // PNG keeps transparency (cartridge-shaped covers); JPEG is smaller for the rest.
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let type = (opaque ? UTType.jpeg : UTType.png).identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
        #else
        return nil
        #endif
    }
}
