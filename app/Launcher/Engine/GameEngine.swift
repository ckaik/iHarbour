import Foundation
import OSLog

/// A game's framework, loaded into the app: the Swift face of the function table in
/// `engine/HarbourEngine.h`.
///
/// The app links none of the games. Each one's framework sits in the app's Frameworks folder and
/// is loaded with `dlopen` the first time the launcher needs it (to extract a ROM, check an
/// archive, or play), then stays loaded for the life of the process.
nonisolated final class GameEngine: @unchecked Sendable {
  enum LoadError: LocalizedError {
    case notIncluded(Game)
    case couldNotLoad(Game, reason: String)
    case incompatible(Game, version: UInt32)

    var errorDescription: String? {
      switch self {
      case .notIncluded(let game):
        "\(game.title) isn't part of this build of iHarbour."
      case .couldNotLoad(let game, let reason):
        "\(game.title) couldn't be loaded: \(reason)"
      case .incompatible(let game, let version):
        """
        \(game.title) was built for another version of iHarbour (engine interface \(version), \
        expected \(HARBOUR_ENGINE_API_VERSION)). Rebuild the app.
        """
      }
    }
  }

  let game: Game
  // Immutable, and the functions behind it are safe to call from any thread except where
  // HarbourEngine.h says otherwise, which the methods below respect.
  private let api: HarbourEngineAPI

  private init(game: Game, api: HarbourEngineAPI) {
    self.game = game
    self.api = api
  }

  // MARK: Loading

  private static let lock = NSLock()
  nonisolated(unsafe) private static var loaded: [Game.ID: GameEngine] = [:]

  /// The framework a game builds into, inside the app bundle.
  static func frameworkURL(for game: Game) -> URL? {
    Bundle.main.privateFrameworksURL?
      .appending(path: "\(game.frameworkName).framework", directoryHint: .isDirectory)
  }

  /// Whether the game's framework is in this build of the app. Builds can leave games out
  /// (`HARBOUR_GAMES` in `app/Config/Local.xcconfig`).
  static func isIncluded(_ game: Game) -> Bool {
    guard let url = frameworkURL(for: game) else { return false }
    return FileManager.default.fileExists(
      atPath: url.appending(path: game.frameworkName).path(percentEncoded: false)
    )
  }

  /// The engine of `game`, loading its framework the first time.
  static func load(_ game: Game) throws -> GameEngine {
    try lock.withLock {
      if let engine = loaded[game.id] {
        return engine
      }

      guard isIncluded(game), let frameworkURL = frameworkURL(for: game) else {
        throw LoadError.notIncluded(game)
      }

      let binary = frameworkURL.appending(path: game.frameworkName).path(percentEncoded: false)
      let start = ContinuousClock.now

      // Some games work out paths in static initializers, which run inside dlopen, so the
      // game's data directory has to be set before (see HarbourEngineAPI.setDataDirectory).
      try? FileManager.default.createDirectory(
        at: game.dataDirectory,
        withIntermediateDirectories: true
      )
      setenv("SHIP_HOME", game.dataDirectory.path(percentEncoded: false), 1)

      // RTLD_LOCAL: each game's framework is its own world, and nothing in the app resolves
      // symbols against it except through dlsym on this handle.
      guard let handle = dlopen(binary, RTLD_NOW | RTLD_LOCAL) else {
        let reason = dlerror().map { String(cString: $0) } ?? "unknown error"
        throw LoadError.couldNotLoad(game, reason: reason)
      }

      guard let symbol = dlsym(handle, "HarbourEngine_GetAPI") else {
        throw LoadError.couldNotLoad(game, reason: "the framework has no HarbourEngine_GetAPI")
      }
      let getAPI = unsafeBitCast(symbol, to: HarbourEngineGetAPIFunction.self)
      guard let api = getAPI()?.pointee else {
        throw LoadError.couldNotLoad(game, reason: "HarbourEngine_GetAPI returned nothing")
      }

      guard api.version == HARBOUR_ENGINE_API_VERSION else {
        throw LoadError.incompatible(game, version: api.version)
      }

      let engine = GameEngine(game: game, api: api)
      api.setDataDirectory(game.dataDirectory.path(percentEncoded: false))
      loaded[game.id] = engine
      Logger.engine.info(
        "Loaded \(game.frameworkName, privacy: .public) in \(ContinuousClock.now - start)"
      )
      return engine
    }
  }

  // MARK: The game

  /// Runs the game until the player quits it. Blocks the main thread the whole time; start it
  /// from a run loop block (see `HarbourEngineAPI.run`).
  @MainActor
  func run(arguments: [String]) -> Int32 {
    // The data directory is process-wide state that loading another game's framework changes.
    api.setDataDirectory(game.dataDirectory.path(percentEncoded: false))

    let cArguments = arguments.map { strdup($0) }
    defer {
      for argument in cArguments {
        free(argument)
      }
    }

    return cArguments.map { UnsafePointer($0) }
      .withUnsafeBufferPointer {
        api.run(Int32($0.count), $0.baseAddress)
      }
  }

  // MARK: ROMs and archives

  /// What the ROM at `url` (a .z64 file) holds, by the game's own checks, or `nil` if the game
  /// can't extract it.
  @concurrent
  func identifyROM(at url: URL) async -> String? {
    var description = [CChar](repeating: 0, count: 256)
    let supported = api.identifyRom(
      url.path(percentEncoded: false),
      &description,
      Int32(description.count)
    )

    guard supported else { return nil }
    return String(
      bytes: description.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
      encoding: .utf8
    ) ?? ""
  }

  /// Extracts the ROM at `url` into the game's folder.
  @concurrent
  func extractROM(at url: URL) async -> Bool {
    api.extractRom(url.path(percentEncoded: false))
  }

  /// Progress of the running extraction, or `nil` if the game doesn't report any.
  var extractionProgress: Double? {
    let progress = api.extractionProgress()
    return progress < 0 ? nil : Double(progress)
  }

  func isArchiveOutdated(at url: URL) -> Bool {
    api.isArchiveOutdated(url.path(percentEncoded: false))
  }

  // MARK: Input

  func setTouchControllerConnected(_ isConnected: Bool) {
    api.setTouchControllerConnected(isConnected)
  }

  func setButton(_ button: HarbourButton, isPressed: Bool) {
    api.setButton(button, isPressed)
  }

  func setAxis(_ axis: HarbourAxis, to value: Double) {
    api.setAxis(axis, Float(value))
  }

  func toggleMenu() {
    api.toggleMenu()
  }

  var isMenuOpen: Bool { api.isMenuOpen() }
}

extension Logger {
  nonisolated static let engine = Logger(subsystem: "org.iharbour", category: "Engine")
}
