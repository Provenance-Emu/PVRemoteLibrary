import Foundation
import PVSystems

/// Names one place games come from: this device, a server, a share or a peer.
public struct LibrarySourceID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// The library on this device.
    public static let local = LibrarySourceID(rawValue: "local")
}

/// What a library screen needs to label a source.
public struct LibrarySourceInfo: Hashable, Codable, Sendable, Identifiable {
    @frozen public enum Kind: String, Codable, Sendable {
        case local, contentServer, romm, peer
    }

    public var id: LibrarySourceID
    public var kind: Kind
    /// Host or device name: the text of the source indicator.
    public var name: String
    /// SF Symbol name: the glyph of the source indicator.
    public var symbol: String

    public init(id: LibrarySourceID, kind: Kind, name: String, symbol: String) {
        self.id = id
        self.kind = kind
        self.name = name
        self.symbol = symbol
    }
}

/// A game as a source lists it.
public struct LibraryGame: Identifiable, Hashable, Codable, Sendable {
    /// Unique across sources: the source's id joined with the source's own game id.
    public var id: String
    public var source: LibrarySourceID
    /// The source's own id for the game, sent back to it unchanged.
    public var sourceGameID: String
    public var title: String
    /// nil when the source's platform maps to no system.
    public var system: SystemIdentifier?
    /// The source's raw platform, shown when `system` is nil.
    public var platformName: String
    /// Lower-case hex, when the source has hashed the file.
    public var md5: String?
    /// Bytes, or 0 when unknown.
    public var sizeBytes: Int64
    public var fileName: String?
    /// Non-nil when the source has a cover for the game.
    public var artKey: String?
    /// How many discs the set has.
    public var discCount: Int
    /// A GameCube or Wii game id, or another id printed on the disc.
    public var gameID: String?
    /// Which disc of the set this entry is.
    public var discNumber: Int?
    public var revision: Int?
    public var ownerLastPlayed: Date?
    public var ownerFavorite: Bool?

    public init(
        source: LibrarySourceID, sourceGameID: String, title: String, system: SystemIdentifier?,
        platformName: String, md5: String? = nil, sizeBytes: Int64 = 0, fileName: String? = nil,
        artKey: String? = nil, discCount: Int = 1, gameID: String? = nil, discNumber: Int? = nil,
        revision: Int? = nil, ownerLastPlayed: Date? = nil, ownerFavorite: Bool? = nil
    ) {
        self.id = source.rawValue + "|" + sourceGameID
        self.source = source
        self.sourceGameID = sourceGameID
        self.title = title
        self.system = system
        self.platformName = platformName
        self.md5 = md5?.lowercased()
        self.sizeBytes = sizeBytes
        self.fileName = fileName
        self.artKey = artKey
        self.discCount = discCount
        self.gameID = gameID
        self.discNumber = discNumber
        self.revision = revision
        self.ownerLastPlayed = ownerLastPlayed
        self.ownerFavorite = ownerFavorite
    }
}

/// A game in the app's own library, reduced to what matching and display need.
public struct LocalGameRef: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var system: SystemIdentifier
    public var md5: String?
    /// Bytes, or 0 when unknown.
    public var sizeBytes: Int64
    public var fileName: String?
    public var gameID: String?
    public var discNumber: Int?
    public var revision: Int?
    /// False for disc sets whose MD5 is not the image's own, so MD5 cannot match them.
    public var isSingleFileImage: Bool
    /// False when the library lists the game but its file is not on this device.
    public var isOnDisk: Bool

    public init(
        id: String, title: String, system: SystemIdentifier, md5: String? = nil, sizeBytes: Int64 = 0,
        fileName: String? = nil, gameID: String? = nil, discNumber: Int? = nil, revision: Int? = nil,
        isSingleFileImage: Bool = true, isOnDisk: Bool = true
    ) {
        self.id = id
        self.title = title
        self.system = system
        self.md5 = md5?.lowercased()
        self.sizeBytes = sizeBytes
        self.fileName = fileName
        self.gameID = gameID
        self.discNumber = discNumber
        self.revision = revision
        self.isSingleFileImage = isSingleFileImage
        self.isOnDisk = isOnDisk
    }
}
