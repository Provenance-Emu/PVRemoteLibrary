# PVRemoteLibrary

One model of "a game somewhere" for Provenance, iFly and iCube: on this device, on an
[emulator content server](https://github.com/Provenance-Emu/emulator-content-server),
on a RomM share or on a nearby peer. It lets an app show a remote library in its normal
library screens, alone or combined with the local one. It draws nothing.

## What is in it

| Type | What it does |
|---|---|
| `LibraryGame`, `LocalGameRef` | A source's game and the app's own game, as plain values |
| `RemoteLibrarySource` | The protocol a server, share or peer implements: pages, covers, fetch |
| `LibraryMatcher` | Decides whether a source's game is already in the library |
| `CombinedLibrary` | Merges local games and any number of catalogues into rows, each game once |
| `RemoteCatalogueStore` | Keeps each source's catalogue on disk so a library opens offline |
| `RemoteCoverCache` | Cover thumbnails on disk, revalidated by ETag |
| `RemoteLibraryBrowser` | The `@Observable` view model an app's library screen reads |
| `RomMSource` (product `PVRemoteLibraryRomM`) | A RomM server as a source |

## Using it

```swift
let browser = RemoteLibraryBrowser(
    cacheDirectory: caches.appendingPathComponent("RemoteLibrary"),
    downloadDirectory: staging,
    hooks: .init(
        localGames: { myLibrary.snapshot() },          // [LocalGameRef]
        importGame: { fetched, game in try await myImporter.add(fetched) }
    )
)
browser.add(source)                 // any RemoteLibrarySource
await browser.open(source.info.id)  // cached catalogue at once, then a refresh
browser.scope = .combined           // or .local, .source(id)
// Draw browser.sections with your own cells; row.availability and row.transfer mark each game.
```

Call `browser.localLibraryChanged()` when the app's library changes.

## How games are matched

Strongest rule first; titles are never compared.

1. Same system, same MD5, and the same size when both sides know it.
2. A recorded link: the local game was downloaded from that entry.
3. Same system, same game id and same disc number.
4. Same system and same file name, ignoring case.

## Tests

```bash
xcrun swift test
```

## Status

First cut, used by no app yet. Not built here: a content-server source (Provenance
adapts its existing `ECSSource`), peer sources, background downloads, save sync.
