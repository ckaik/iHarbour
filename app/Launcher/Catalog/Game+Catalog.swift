import Foundation
import SwiftUI

// The games iHarbour hosts. Each has a port in ports/<id>/ and a submodule in games/.
//
// ROM checksums come from each project's documentation (docs/supportedHashes.json, README.md) and
// are of the .z64 form. Setting names are the CVars each game's libultraship build uses.
//
// Websites are URL literals, which always parse, so each game ignores NeverForceUnwrap.

nonisolated extension Game {
  static let all: [Game] = [
    .shipOfHarkinian,
    .twoShip,
    .ghostship,
    .spaghettiKart,
    .starship,
    .lighthouse,
    .paperBoat,
  ]

  // swift-format-ignore: NeverForceUnwrap
  static let shipOfHarkinian = Game(
    id: "soh",
    title: "Ship of Harkinian",
    frameworkName: "ShipOfHarkinian",
    folderName: "Ship of Harkinian",
    configFileName: "shipofharkinian.json",
    imageName: "Game-soh",
    tint: Color(red: 0.36, green: 0.52, blue: 0.93),
    archives: [
      Archive(fileName: "oot.o2r", title: "Game assets", isMain: true),
      Archive(fileName: "oot-mq.o2r", title: "MQ assets", isMain: true),
    ],
    roms: [
      ROM(sha1: "ad69c91157f6705e8ab06c79fe08aad47bb57ba7", title: "NTSC 1.0 (US)"),
      ROM(sha1: "d3ecb253776cd847a5aa63d859d8c89a2f37b364", title: "NTSC 1.1 (US)"),
      ROM(sha1: "41b3bdc48d98c48529219919015a1af22f5057c2", title: "NTSC 1.2 (US)"),
      ROM(sha1: "c892bbda3993e66bd0d56a10ecd30b1ee612210f", title: "NTSC 1.0 (JP)"),
      ROM(sha1: "dbfc81f655187dc6fefd93fa6798face770d579d", title: "NTSC 1.1 (JP)"),
      ROM(sha1: "fa5f5942b27480d60243c2d52c0e93e26b9e6b86", title: "NTSC 1.2 (JP)"),
      ROM(sha1: "328a1f1beba30ce5e178f031662019eb32c5f3b5", title: "PAL 1.0"),
      ROM(sha1: "cfbb98d392e4a9d39da8285d10cbef3974c2f012", title: "PAL 1.1"),
      ROM(sha1: "b82710ba2bd3b4c6ee8aa1a7e9acf787dfc72e9b", title: "NTSC GC (US)"),
      ROM(sha1: "0769c84615422d60f16925cd859593cdfa597f84", title: "NTSC GC (JP)"),
      ROM(
        sha1: "2ce2d1a9f0534c9cd9fa04ea5317b80da21e5e73",
        title: "NTSC GC (JP, Collector's Edition)",
      ),
      ROM(sha1: "0227d7c0074f2d0ac935631990da8ec5914597b4", title: "PAL GC"),
      ROM(sha1: "cee6bc3c2a634b41728f2af8da54d9bf8cc14099", title: "PAL GC (Debug)"),
      ROM(sha1: "8b5d13aac69bfbf989861cfdc50b1d840945fc1d", title: "MQ NTSC (US)"),
      ROM(sha1: "dd14e143c4275861fe93ea79d0c02e36ae8c6c2f", title: "MQ NTSC (JP)"),
      ROM(sha1: "f46239439f59a2a594ef83cf68ef65043b1bffe2", title: "MQ PAL"),
      ROM(sha1: "079b855b943d6ad8bd1eb026c0ed169ecbdac7da", title: "MQ PAL (Debug)"),
      ROM(sha1: "50bebedad9e0f10746a52b07239e47fa6c284d03", title: "MQ PAL (Debug)"),
      ROM(sha1: "cfecfdc58d650e71a200c81f033de4e6d617a9f6", title: "MQ PAL (Debug)"),
    ],
    gameCodes: ["ZL"],
    settings: SettingNames(
      internalResolution: "gSettings.InternalResolution",
      msaa: "gSettings.MSAAValue",
      textureFilter: "gSettings.TextureFilter",
      frameRate: "gSettings.InterpolationFPS",
      matchesRefreshRate: "gSettings.MatchRefreshRate",
      menuScale: "gSettings.ImGuiScale",
      masterVolume: "gSettings.Volume.Master",
      masterVolumeDefault: 40,
    ),
    originalFrameRate: 20,
    menuDescription: """
      Enhancements, cheats, the randomizer, and controller mapping are in the in-game menu. Tap \
      MENU while playing to open it.
      """,
    website: URL(string: "https://github.com/HarbourMasters/Shipwright")!,
  )

  // swift-format-ignore: NeverForceUnwrap
  static let spaghettiKart = Game(
    id: "spaghettikart",
    title: "SpaghettiKart",
    frameworkName: "SpaghettiKart",
    folderName: "SpaghettiKart",
    configFileName: "spaghettify.cfg.json",
    imageName: "Game-spaghettikart",
    tint: Color(red: 0.90, green: 0.22, blue: 0.21),
    archives: [
      Archive(fileName: "mk64.o2r", title: "Game assets", isMain: true)
    ],
    roms: [
      ROM(sha1: "579c48e211ae952530ffc8738709f078d5dd215e", title: "US")
    ],
    gameCodes: ["KT"],
    settings: SettingNames(
      internalResolution: "gInternalResolution",
      msaa: "gMSAAValue",
      textureFilter: "gTextureFilter",
      frameRate: "gInterpolationFPS",
      matchesRefreshRate: "gMatchRefreshRate",
      // The game's menu scale (gSettings.Menu.Scale) is a 1...2 float with its own rules.
      menuScale: nil,
      masterVolume: "gGameMasterVolume",
      masterVolumeIsFloat: true,
    ),
    originalFrameRate: 30,
    menuDescription: """
      Enhancements, cheats, rulesets, and controller mapping are in the in-game menu. Tap MENU \
      while playing to open it.
      """,
    website: URL(string: "https://github.com/HarbourMasters/SpaghettiKart")!,
  )

  // swift-format-ignore: NeverForceUnwrap
  static let lighthouse = Game(
    id: "lighthouse",
    title: "Lighthouse",
    frameworkName: "Lighthouse",
    folderName: "Lighthouse",
    configFileName: "lighthouse.cfg.json",
    imageName: "Game-lighthouse",
    tint: Color(red: 0.95, green: 0.66, blue: 0.18),
    archives: [
      Archive(fileName: "bk.o2r", title: "Game assets", isMain: true),
      Archive(fileName: "mods/~lang/bkus.o2r", title: "US English text", isMain: false),
      Archive(
        fileName: "mods/~lang/bkpal.o2r",
        title: "PAL texts (English, French, German)",
        isMain: false
      ),
      Archive(fileName: "mods/~lang/bkjp.o2r", title: "Japanese text", isMain: false),
    ],
    roms: [
      ROM(sha1: "1fe1632098865f639e22c11b9a81ee8f29c75d7a", title: "US 1.0"),
      ROM(sha1: "ded6ee166e740ad1bc810fd678a84b48e245ab80", title: "US 1.1"),
      ROM(sha1: "bb359a75941df74bf7290212c89fbc6e2c5601fe", title: "PAL"),
      ROM(sha1: "90726d7e7cd5bf6cdfd38f45c9acbf4d45bd9fd8", title: "JP"),
    ],
    gameCodes: ["BK"],
    settings: SettingNames(
      internalResolution: "gSettings.InternalResolution",
      msaa: "gSettings.MSAAValue",
      textureFilter: "gSettings.TextureFilter",
      frameRate: "gSettings.InterpolationFPS",
      matchesRefreshRate: "gSettings.MatchRefreshRate",
      menuScale: "gSettings.ImGuiScale",
      masterVolume: "gSettings.Volume.Master",
      masterVolumeDefault: 40,
    ),
    originalFrameRate: 30,
    menuDescription: """
      Enhancements, the randomizer, mods, language packs, and controller mapping are in the \
      in-game menu. Tap MENU while playing to open it. A ROM of another region added after the \
      first becomes a language pack.
      """,
    website: URL(string: "https://github.com/IsleOPorts/Lighthouse")!,
  )

  // swift-format-ignore: NeverForceUnwrap
  static let paperBoat = Game(
    id: "paperboat",
    title: "PaperBoat",
    frameworkName: "PaperBoat",
    folderName: "PaperBoat",
    configFileName: "paperboat.cfg.json",
    imageName: "Game-paperboat",
    tint: Color(red: 0.91, green: 0.33, blue: 0.29),
    archives: [
      Archive(fileName: "pm64.o2r", title: "Game assets", isMain: true)
    ],
    roms: [
      ROM(sha1: "3837f44cda784b466c9a2d99df70d77c322b97a0", title: "NTSC (US)")
    ],
    gameCodes: ["MQ"],
    settings: SettingNames(
      internalResolution: "gSettings.InternalResolution",
      msaa: "gSettings.MSAAValue",
      textureFilter: "gSettings.TextureFilter",
      frameRate: "gSettings.InterpolationFPS",
      matchesRefreshRate: "gSettings.MatchRefreshRate",
      menuScale: "gSettings.ImGuiScale",
      masterVolume: "gSettings.Volume.Master",
    ),
    originalFrameRate: 30,
    menuDescription: """
      Enhancements, cheats, graphics and audio settings, mods, and controller mapping are in the \
      in-game menu. Tap MENU while playing to open it.
      """,
    website: URL(string: "https://github.com/HarbourMasters/PaperBoat")!,
  )

  // swift-format-ignore: NeverForceUnwrap
  static let twoShip = Game(
    id: "2ship",
    title: "2 Ship 2 Harkinian",
    frameworkName: "TwoShip2Harkinian",
    folderName: "2 Ship 2 Harkinian",
    configFileName: "2ship2harkinian.json",
    imageName: "Game-2ship",
    tint: Color(red: 0.58, green: 0.34, blue: 0.78),
    archives: [
      Archive(fileName: "mm.o2r", title: "Game assets", isMain: true)
    ],
    roms: [
      ROM(sha1: "d6133ace5afaa0882cf214cf88daba39e266c078", title: "NTSC 1.0 (US)"),
      ROM(sha1: "9743aa026e9269b339eb0e3044cd5830a440c1fd", title: "NTSC GC (US)"),
    ],
    gameCodes: ["ZS"],
    settings: SettingNames(
      internalResolution: "gSettings.InternalResolution",
      msaa: "gSettings.MSAAValue",
      textureFilter: "gSettings.TextureFilter",
      frameRate: "gInterpolationFPS",
      matchesRefreshRate: "gMatchRefreshRate",
      menuScale: "gSettings.ImGuiScale",
      masterVolume: "gSettings.Audio.MasterVolume",
      masterVolumeIsFloat: true,
    ),
    originalFrameRate: 20,
    menuDescription: """
      Enhancements, cheats, the randomizer, and controller mapping are in the in-game menu. Tap \
      MENU while playing to open it.
      """,
    website: URL(string: "https://github.com/2ship2harkinian/2ship2harkinian")!,
  )

  // swift-format-ignore: NeverForceUnwrap
  static let ghostship = Game(
    id: "ghostship",
    title: "Ghostship",
    frameworkName: "Ghostship",
    folderName: "Ghostship",
    configFileName: "ghostship.cfg.json",
    imageName: "Game-ghostship",
    tint: Color(red: 0.89, green: 0.20, blue: 0.18),
    archives: [
      Archive(fileName: "sm64.o2r", title: "Game assets", isMain: true)
    ],
    roms: [
      ROM(sha1: "9bef1128717f958171a4afac3ed78ee2bb4e86ce", title: "US"),
      ROM(sha1: "8a20a5c83d6ceb0f0506cfc9fa20d8f438cafe51", title: "JP"),
    ],
    gameCodes: ["SM"],
    settings: SettingNames(
      internalResolution: "gSettings.InternalResolution",
      msaa: "gSettings.MSAAValue",
      textureFilter: "gSettings.TextureFilter",
      frameRate: "gSettings.InterpolationFPS",
      matchesRefreshRate: "gSettings.MatchRefreshRate",
      menuScale: "gSettings.ImGuiScale",
      masterVolume: "gSettings.Volume.Master",
    ),
    originalFrameRate: 30,
    menuDescription: """
      Enhancements, cheats, mods, and controller mapping are in the in-game menu. Tap MENU while \
      playing to open it.
      """,
    website: URL(string: "https://github.com/HarbourMasters/Ghostship")!,
  )

  // swift-format-ignore: NeverForceUnwrap
  static let starship = Game(
    id: "starship",
    title: "Starship",
    frameworkName: "Starship",
    folderName: "Starship",
    configFileName: "starship.cfg.json",
    imageName: "Game-starship",
    tint: Color(red: 0.93, green: 0.42, blue: 0.16),
    archives: [
      Archive(fileName: "sf64.o2r", title: "Game assets", isMain: true),
      Archive(fileName: "mods/sf64jp.o2r", title: "Japanese voices", isMain: false),
      Archive(fileName: "mods/sf64eu.o2r", title: "European voices", isMain: false),
      Archive(fileName: "mods/sf64cn.o2r", title: "Chinese voices", isMain: false),
    ],
    roms: [
      ROM(sha1: "09f0d105f476b00efa5303a3ebc42e60a7753b7a", title: "US 1.1"),
      ROM(sha1: "f7475fb11e7e6830f82883412638e8390791ab87", title: "US 1.1 (uncompressed)"),
      ROM(sha1: "d8b1088520f7c5f81433292a9258c1184afa1457", title: "US 1.0"),
      ROM(sha1: "63b69f0ef36306257481afc250f9bc304c7162b2", title: "US 1.0 (uncompressed)"),
      ROM(sha1: "9bd71afbecf4d0a43146e4e7a893395e19bf3220", title: "JP (Japanese voices)"),
      ROM(
        sha1: "d064229a32cc05ab85e2381ce07744eb3ffaf530",
        title: "JP, uncompressed (Japanese voices)",
      ),
      ROM(sha1: "05b307b8804f992af1a1e2fbafbd588501fdf799", title: "EU (European voices)"),
      ROM(
        sha1: "09f5d5c14219fc77a36c5a6ad5e63f7abd8b3385",
        title: "EU, uncompressed (European voices)",
      ),
      ROM(
        sha1: "e6dad7523ff8f83fad6fbdb59d472b4f76340c2b",
        title: "EU, Spanish translation (Spanish voices)",
      ),
      ROM(sha1: "c8a10699dea52f4bb2e2311935c1376dfb352e7a", title: "CN (Chinese voices)"),
      ROM(
        sha1: "3a05aba5549fa71e8b16a0c6e2c8481b070818a9",
        title: "CN, uncompressed (Chinese voices)",
      ),
    ],
    gameCodes: ["FX"],
    settings: SettingNames(
      internalResolution: "gInternalResolution",
      msaa: "gMSAAValue",
      textureFilter: "gTextureFilter",
      frameRate: "gInterpolationFPS",
      matchesRefreshRate: "gMatchRefreshRate",
      menuScale: nil,
      masterVolume: "gGameMasterVolume",
      masterVolumeIsFloat: true,
      frameRateDefault: 60,
    ),
    originalFrameRate: 30,
    menuDescription: """
      Enhancements, cheats, graphics and audio settings, and controller mapping are in the \
      in-game menu bar. Tap MENU while playing to open it. Only US ROMs make the game playable; \
      JP, EU and CN ROMs add their voice acting.
      """,
    website: URL(string: "https://github.com/HarbourMasters/Starship")!,
  )
}
