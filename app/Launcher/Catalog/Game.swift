import Foundation
import SwiftUI

/// A game iHarbour can host: what the launcher knows about it without loading its framework.
///
/// The list itself is in `Game+Catalog.swift`. The ids match the folders in `ports/`.
nonisolated struct Game: Identifiable, Hashable, Sendable {
  /// A file the game loads its assets from, extracted from a ROM into the game's folder.
  struct Archive: Hashable, Sendable {
    /// The archive's path inside the game's folder: a file name, or a path into a subfolder
    /// (`mods/…`) for add-ons the game loads from there.
    let fileName: String
    let title: String
    /// Whether this archive alone is enough to play. Games with more than one (an MQ variant,
    /// voice or language packs) need one of these at least.
    let isMain: Bool
  }

  /// A ROM dump the game supports, by the SHA-1 of its .z64 (big-endian) form.
  struct ROM: Hashable, Sendable {
    let sha1: String
    let title: String
  }

  /// The game's names for the settings the launcher offers. `nil` leaves a setting out.
  struct SettingNames: Hashable, Sendable {
    var internalResolution: String?
    var msaa: String?
    var textureFilter: String?
    var frameRate: String?
    var matchesRefreshRate: String?
    var menuScale: String?
    var masterVolume: String?

    /// Whether the master volume is a 0...1 float rather than a 0...100 integer.
    var masterVolumeIsFloat = false
    /// The game's default master volume, 0...100, shown while the setting is unset.
    var masterVolumeDefault = 100
    /// The game's default frame rate, if it isn't the original one.
    var frameRateDefault: Int?
  }

  let id: String
  /// The port's name.
  let title: String

  let frameworkName: String
  /// The game's folder in the app's Documents, which the Files app shows.
  let folderName: String
  /// The config file libultraship keeps the game's settings in, inside its folder.
  let configFileName: String

  /// An image in the asset catalog.
  let imageName: String
  let tint: Color

  let archives: [Archive]
  let roms: [ROM]
  /// Game codes (the two letters at 0x3C of the ROM header) of the game's ROMs, for recognizing
  /// a dump whose checksum isn't in `roms`.
  let gameCodes: [String]

  let settings: SettingNames?
  /// The frame rate the game originally ran at, above which frames are interpolated.
  let originalFrameRate: Int

  /// What the in-game menu has to offer, for the launcher to point at.
  let menuDescription: String
  let website: URL

  var dataDirectory: URL {
    Self.documentsDirectory.appending(path: folderName, directoryHint: .isDirectory)
  }

  var configFile: URL {
    dataDirectory.appending(path: configFileName, directoryHint: .notDirectory)
  }

  static var documentsDirectory: URL {
    URL.documentsDirectory
  }

  static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

nonisolated extension Game {
  static func withID(_ id: Game.ID) -> Game? {
    all.first { $0.id == id }
  }

  /// The game and dump a ROM's checksum belongs to.
  static func match(sha1: String) -> (game: Game, rom: ROM)? {
    let sha1 = sha1.lowercased()

    for game in all {
      if let rom = game.roms.first(where: { $0.sha1 == sha1 }) {
        return (game, rom)
      }
    }
    return nil
  }

  /// The game a ROM with this header game code belongs to, if any.
  static func match(gameCode: String) -> Game? {
    guard !gameCode.isEmpty else { return nil }
    return all.first { $0.gameCodes.contains(gameCode) }
  }
}
