import Foundation
import OSLog
import Observation
import UIKit

/// The launcher's state: which games are here and ready, ROM imports, and the one game session a
/// process gets.
@Observable
final class Library {
  enum Session: Equatable {
    case idle
    case running(Game)
    /// A game ran and quit. Games keep global state they never tear down, so none can start
    /// again in this process.
    case ended(Game)

    var isIdle: Bool { self == .idle }
  }

  /// A ROM on its way to becoming a game's archive.
  struct Import: Equatable {
    let fileName: String
    var phase: ImportPhase
  }

  enum ImportPhase: Equatable {
    case reading
    case extracting(Game, description: String)
  }

  struct Problem {
    let title: String
    let message: String
  }

  /// What just finished importing, for a confirmation.
  struct ImportResult {
    let game: Game
    let description: String
  }

  let games: [Game]
  let touchControls: TouchControlsSettings

  private(set) var archives: [Game.ID: [InstalledArchive]] = [:]
  /// Archives the game found outdated (made by an older version of it). Filled in by
  /// `checkArchives(of:)`, which needs the game's framework.
  private(set) var outdatedArchives: Set<URL> = []
  private(set) var looseROMs: [ROMFile] = []
  private(set) var session: Session = .idle
  private(set) var currentImport: Import?

  var problem: Problem?
  var importResult: ImportResult?

  @ObservationIgnored private var touchControlsWindow: TouchControlsWindow?
  @ObservationIgnored private var importingEngine: GameEngine?

  init(games: [Game] = Game.all, touchControls: TouchControlsSettings = TouchControlsSettings()) {
    self.games = games
    self.touchControls = touchControls

    for game in games {
      try? FileManager.default.createDirectory(
        at: game.dataDirectory,
        withIntermediateDirectories: true
      )
    }

    refresh()
  }

  // MARK: State

  func isIncluded(_ game: Game) -> Bool {
    GameEngine.isIncluded(game)
  }

  func archives(of game: Game) -> [InstalledArchive] {
    archives[game.id] ?? []
  }

  func isOutdated(_ archive: InstalledArchive) -> Bool {
    outdatedArchives.contains(archive.url)
  }

  /// Whether the game has what it needs to start: a main archive that isn't outdated.
  func isReady(_ game: Game) -> Bool {
    archives(of: game).contains { $0.isMain && !isOutdated($0) }
  }

  func canPlay(_ game: Game) -> Bool {
    guard session.isIdle, currentImport == nil, isIncluded(game) else { return false }
    return isReady(game) || Self.allowsPlayWithoutArchives
  }

  var canImport: Bool { session.isIdle && currentImport == nil }

  /// Progress of the running extraction, if the game reports any.
  var extractionProgress: Double? { importingEngine?.extractionProgress }

  /// Picks up files that came and went behind the launcher's back, through the Files app.
  func refresh() {
    for game in games {
      archives[game.id] = InstalledArchive.archives(of: game)
    }

    looseROMs = ROMFile.all()
  }

  /// Asks the game whether its main archives are current (add-ons such as voice packs have
  /// versions of their own). Loads the game's framework.
  func checkArchives(of game: Game) {
    // Loading or calling into a game points libultraship's data directory (SHIP_HOME, which is
    // process-wide) at that game. While an import runs, that would redirect the extraction into
    // the other game's folder, so checks wait until it's done.
    guard currentImport == nil else { return }

    let archives = archives(of: game).filter(\.isMain)
    guard !archives.isEmpty, isIncluded(game), let engine = try? GameEngine.load(game) else {
      return
    }

    for archive in archives {
      if engine.isArchiveOutdated(at: archive.url) {
        outdatedArchives.insert(archive.url)
      } else {
        outdatedArchives.remove(archive.url)
      }
    }
  }

  // MARK: Importing ROMs

  /// Works out which game the ROM at `url` belongs to and extracts it into that game's folder.
  /// `expectedGame` is the game whose page the import started from; it's used when the ROM
  /// can't be recognized by its checksum or game code.
  func importROM(at url: URL, expectedGame: Game? = nil) async {
    guard canImport else { return }

    currentImport = Import(fileName: url.lastPathComponent, phase: .reading)
    defer {
      currentImport = nil
      importingEngine = nil
      refresh()
    }

    let image: ROMImage
    do {
      image = try await ROMImage.prepare(from: url)
    } catch {
      Logger.library.error("Couldn't read ROM \(url.lastPathComponent): \(error)")
      problem = Problem(title: "Couldn't Read ROM", message: error.localizedDescription)
      return
    }
    defer { image.discard() }

    let known = Game.match(sha1: image.sha1)
    guard let game = known?.game ?? Game.match(gameCode: image.gameCode) ?? expectedGame else {
      problem = .unrecognizedROM(named: image.originalName)
      return
    }

    let engine: GameEngine
    do {
      engine = try GameEngine.load(game)
    } catch {
      problem = Problem(title: "Can't Extract ROM", message: error.localizedDescription)
      return
    }

    guard let gameDescription = await engine.identifyROM(at: image.url) else {
      problem = .unsupportedROM(named: image.originalName, game: game)
      return
    }

    // "PAL, language pack": the dump's name when the catalog knows it, plus what only the game can
    // tell.
    let parts = [known?.rom.title, gameDescription].compactMap(\.self).filter { !$0.isEmpty }
    let description = parts.isEmpty ? "ROM" : parts.joined(separator: ", ")

    Logger.library.info(
      "Extracting \(description) (\(image.sha1)) from \(image.originalName) for \(game.id)"
    )
    currentImport?.phase = .extracting(game, description: description)
    importingEngine = engine

    guard await engine.extractROM(at: image.url) else {
      problem = Problem(
        title: "Extraction Failed",
        message:
          "\(game.title) couldn't extract \(image.originalName). Try again, or try another ROM.",
      )
      return
    }

    refresh()
    checkArchives(of: game)
    importResult = ImportResult(game: game, description: description)
  }

  func delete(_ archive: InstalledArchive) {
    remove(archive.url)
    outdatedArchives.remove(archive.url)
  }

  func delete(_ rom: ROMFile) {
    remove(rom.url)
  }

  // MARK: Playing

  /// Starts `game` on top of the launcher.
  func play(_ game: Game) {
    guard canPlay(game), let scene = Self.activeWindowScene else { return }

    let engine: GameEngine
    do {
      engine = try GameEngine.load(game)
    } catch {
      problem = Problem(title: "Can't Start \(game.title)", message: error.localizedDescription)
      return
    }

    // The game deletes archives it considers outdated when it starts, so don't let it.
    for archive in archives(of: game)
    where archive.isMain && engine.isArchiveOutdated(at: archive.url) {
      outdatedArchives.insert(archive.url)
    }

    guard isReady(game) || Self.allowsPlayWithoutArchives else {
      problem = .outdatedArchives(game: game)
      return
    }

    session = .running(game)

    let configuration = touchControls.configuration
    engine.setTouchControllerConnected(configuration.showsControls)
    touchControlsWindow = TouchControlsWindow(
      windowScene: scene,
      configuration: configuration,
      engine: engine,
    )

    scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { error in
      Logger.library.info("Didn't switch to landscape: \(error)")
    }

    // The game doesn't return from its main loop until it quits. Entered from this button's
    // action, it would stall UIKit's event dispatch; entered from a main-queue block, it would
    // stall the main queue and with it SwiftUI and the main actor. A run loop block has neither
    // problem, and the game keeps the run loop turning (see HarbourEngineAPI.run).
    RunLoop.main.perform { [self] in
      // RunLoop.main runs its blocks on the main thread.
      MainActor.assumeIsolated { run(game, engine: engine) }
    }
  }

  private func run(_ game: Game, engine: GameEngine) {
    Logger.library.info("Starting \(game.id)")
    // argv[0], as on the desktop. The launcher extracts ROMs itself, so it passes none.
    let status = engine.run(arguments: [game.frameworkName])
    Logger.library.info("\(game.id) quit with status \(status)")

    touchControlsWindow?.tearDown()
    touchControlsWindow = nil
    session = .ended(game)
    refresh()
  }

  // MARK: Launch arguments for testing

  /// Scripted smoke tests, for simulators that input automation can't reach. Debug builds launched
  /// with `-HarbourAutoImport YES` import every ROM in Files (see `looseROMs`), and with
  /// `-HarbourAutoPlay <game id>` then start that game.
  func runLaunchArguments() async {
    #if DEBUG
      let defaults = UserDefaults.standard

      if defaults.bool(forKey: "HarbourAutoImport") {
        for rom in looseROMs {
          await importROM(at: rom.url)
          importResult = nil
        }
      }

      if let id = defaults.string(forKey: "HarbourAutoPlay"), let game = Game.withID(id) {
        play(game)
      }
    #endif
  }

  /// Debug builds launched with `-HarbourAllowPlayWithoutArchives YES` can start games without
  /// their archives. Most then show their own "missing archive" prompt, which is enough to check
  /// that a game loads, renders, and takes touches without a ROM at hand.
  private static var allowsPlayWithoutArchives: Bool {
    #if DEBUG
      UserDefaults.standard.bool(forKey: "HarbourAllowPlayWithoutArchives")
    #else
      false
    #endif
  }

  // MARK: Helpers

  private func remove(_ url: URL) {
    do {
      try FileManager.default.removeItem(at: url)
    } catch {
      Logger.library.error("Couldn't delete \(url.lastPathComponent): \(error)")
      problem = Problem(title: "Couldn't Delete File", message: error.localizedDescription)
    }

    refresh()
  }

  static var activeWindowScene: UIWindowScene? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
  }
}

extension Library.Problem {
  static func unrecognizedROM(named name: String) -> Self {
    Self(
      title: "Unrecognized ROM",
      message: """
        iHarbour doesn't recognize \(name) as a ROM of any of its games. It needs an unmodified \
        dump of a supported version; each game's page lists what it takes.
        """,
    )
  }

  static func unsupportedROM(named name: String, game: Game) -> Self {
    Self(
      title: "Unsupported ROM",
      message: """
        \(name) looks like a ROM for \(game.title), but not a version it supports. It needs an \
        unmodified dump of a supported version.
        """,
    )
  }

  static func outdatedArchives(game: Game) -> Self {
    Self(
      title: "Game Files Outdated",
      message: """
        \(game.title)'s game files come from an older version of the game. Extract the ROM \
        again to play.
        """,
    )
  }
}

extension Logger {
  static let library = Logger(subsystem: "org.iharbour", category: "Library")
}
