import Foundation

/// A ROM the player put into the app's Documents, through the Files app or Finder.
nonisolated struct ROMFile: Identifiable, Hashable, Sendable {
  /// The extensions iHarbour recognizes, in any case.
  static let pathExtensions: Set<String> = ["z64", "n64", "v64"]

  let url: URL

  var id: URL { url }
  var name: String { url.lastPathComponent }

  /// ROMs directly inside Documents or inside a game's folder.
  static func all() -> [Self] {
    let directories = [Game.documentsDirectory] + Game.all.map(\.dataDirectory)
    return directories.flatMap(files(in:))
  }

  private static func files(in directory: URL) -> [Self] {
    let contents =
      (try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles],
      )) ?? []

    return
      contents
      .filter { pathExtensions.contains($0.pathExtension.lowercased()) }
      .sorted {
        $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
      }
      .map(Self.init(url:))
  }
}
