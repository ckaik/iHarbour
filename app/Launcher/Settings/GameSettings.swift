import Foundation
import Observation

/// The settings of one game the launcher offers before it starts.
///
/// They live in the game's own config file under its CVar names (`Game.SettingNames`), so the
/// in-game menu shows the same values. Everything else stays in the in-game menu.
@Observable
final class GameSettings {
  enum TextureFilter: Int, CaseIterable, Identifiable {
    // Values of libultraship's FilteringMode.
    case threePoint = 0
    case linear = 1
    /// libultraship's FILTER_NONE: nearest-neighbour sampling.
    case nearest = 2

    var id: Self { self }

    var title: String {
      switch self {
      case .threePoint: "Three-point (original)"
      case .linear: "Linear"
      case .nearest: "None (sharp)"
      }
    }
  }

  enum MenuSize: Int, CaseIterable, Identifiable {
    // Indices into libultraship's ImGui scale options.
    case small = 0
    case normal = 1
    case large = 2
    case extraLarge = 3

    var id: Self { self }

    var title: String {
      switch self {
      case .small: "Small"
      case .normal: "Normal"
      case .large: "Large"
      case .extraLarge: "Extra Large"
      }
    }
  }

  let game: Game
  let names: Game.SettingNames

  // Defaults match libultraship's, so an untouched setting reads the same here and in the game.
  var internalResolution = 1.0 {
    didSet { store(names.internalResolution) { setFloat($0, internalResolution) } }
  }

  var msaa = 1 {
    didSet { store(names.msaa) { setInt($0, msaa) } }
  }

  var textureFilter = TextureFilter.threePoint {
    didSet { store(names.textureFilter) { setInt($0, textureFilter.rawValue) } }
  }

  var frameRate: Int {
    didSet { store(names.frameRate) { setInt($0, frameRate) } }
  }

  var matchesRefreshRate = false {
    didSet { store(names.matchesRefreshRate) { setInt($0, matchesRefreshRate ? 1 : 0) } }
  }

  var menuSize = MenuSize.normal {
    didSet { store(names.menuSize) { setInt($0, menuSize.rawValue) } }
  }

  /// 0...100.
  var masterVolume = 100 {
    didSet {
      store(names.masterVolume) { name in
        if names.masterVolumeIsFloat {
          setFloat(name, Double(masterVolume) / 100)
        } else {
          setInt(name, masterVolume)
        }
      }
    }
  }

  @ObservationIgnored private let configPath: String
  /// Set while values are read in, so reading them doesn't write them straight back.
  @ObservationIgnored private var isLoading = false

  init?(game: Game) {
    guard let names = game.settings else { return nil }

    self.game = game
    self.names = names
    configPath = game.configFile.path(percentEncoded: false)
    frameRate = game.originalFrameRate

    isLoading = true
    defer { isLoading = false }
    reload()
  }

  /// Puts every setting the launcher offers back to the game's default.
  func reset() {
    for name in names.all {
      HarbourConfig_Clear(configPath, name)
    }

    isLoading = true
    defer { isLoading = false }
    reload()
  }

  private func reload() {
    internalResolution = float(names.internalResolution, default: 1)
    msaa = int(names.msaa, default: 1)
    textureFilter = TextureFilter(rawValue: int(names.textureFilter, default: 0)) ?? .threePoint
    frameRate = int(names.frameRate, default: names.frameRateDefault ?? game.originalFrameRate)
    matchesRefreshRate = int(names.matchesRefreshRate, default: 0) != 0
    menuSize = MenuSize(rawValue: int(names.menuSize, default: 1)) ?? .normal

    if names.masterVolumeIsFloat {
      let fallback = Double(names.masterVolumeDefault) / 100
      masterVolume = Int((float(names.masterVolume, default: fallback) * 100).rounded())
    } else {
      masterVolume = int(names.masterVolume, default: names.masterVolumeDefault)
    }
  }

  private func store(_ name: String?, _ save: (String) -> Void) {
    guard !isLoading, let name else { return }

    try? FileManager.default.createDirectory(
      at: game.dataDirectory,
      withIntermediateDirectories: true
    )
    save(name)
  }

  private func int(_ name: String?, default defaultValue: Int) -> Int {
    guard let name else { return defaultValue }
    return Int(HarbourConfig_GetInt(configPath, name, Int32(defaultValue)))
  }

  private func float(_ name: String?, default defaultValue: Double) -> Double {
    guard let name else { return defaultValue }
    return Double(HarbourConfig_GetFloat(configPath, name, Float(defaultValue)))
  }

  private func setInt(_ name: String, _ value: Int) {
    HarbourConfig_SetInt(configPath, name, Int32(value))
  }

  private func setFloat(_ name: String, _ value: Double) {
    HarbourConfig_SetFloat(configPath, name, Float(value))
  }
}

extension Game.SettingNames {
  var all: [String] {
    [
      internalResolution, msaa, textureFilter, frameRate, matchesRefreshRate, menuScale,
      masterVolume,
    ]
    .compactMap(\.self)
  }

  var menuSize: String? { menuScale }
}
