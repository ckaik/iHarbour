import Foundation

/// An archive extracted from a ROM, in a game's folder.
nonisolated struct InstalledArchive: Identifiable, Hashable, Sendable {
  /// What the archive is, if the game's catalog entry knows it.
  let kind: Game.Archive?
  let url: URL
  let byteCount: Int64
  let modificationDate: Date?

  var id: URL { url }
  var title: String { kind?.title ?? url.lastPathComponent }
  var isMain: Bool { kind?.isMain ?? false }

  /// The archives directly inside `game`'s folder, plus the add-ons its catalog entry names in
  /// subfolders (voice and language packs in `mods/`).
  static func archives(of game: Game) -> [Self] {
    let folder = game.dataDirectory
    let contents =
      (try? FileManager.default.contentsOfDirectory(
        at: folder,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles],
      )) ?? []

    // Paths relative to the game's folder, as the catalog names them.
    let topLevel =
      contents
      .filter { ["o2r", "otr"].contains($0.pathExtension.lowercased()) }
      .map(\.lastPathComponent)
    let addOns = game.archives.map(\.fileName).filter { $0.contains("/") }

    return (topLevel + addOns)
      .compactMap { relativePath in
        let url = folder.appending(path: relativePath, directoryHint: .notDirectory)
        guard
          let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]
          ),
          let byteCount = values.fileSize
        else { return nil }

        return Self(
          kind: game.archives.first {
            $0.fileName.caseInsensitiveCompare(relativePath) == .orderedSame
          },
          url: url,
          byteCount: Int64(byteCount),
          modificationDate: values.contentModificationDate,
        )
      }
      // In the catalog's order, unknown ones last.
      .sorted { lhs, rhs in
        let order = { (archive: Self) in
          game.archives.firstIndex { $0 == archive.kind } ?? game.archives.count
        }
        return (order(lhs), lhs.url.lastPathComponent) < (order(rhs), rhs.url.lastPathComponent)
      }
  }
}
