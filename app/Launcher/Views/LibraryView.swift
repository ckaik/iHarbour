import SwiftUI
import UniformTypeIdentifiers

/// The launcher's home: every game, whether it's ready to play, and ROMs waiting to be extracted.
struct LibraryView: View {
  @Bindable var library: Library
  @Environment(\.scenePhase) private var scenePhase

  @State private var path: [Game] = []
  @State private var isImportingROM = false
  @State private var isShowingSettings = false
  /// A ROM waiting for import; set to start one.
  @State private var romToImport: ROMToImport?

  var body: some View {
    NavigationStack(path: $path) {
      List {
        if case .ended(let game) = library.session {
          SessionEndedSection(game: game)
        }

        if let currentImport = library.currentImport {
          Section("Importing") {
            ImportRow(currentImport: currentImport) { library.extractionProgress }
          }
        }

        Section {
          ForEach(library.games) { game in
            NavigationLink(value: game) {
              GameRow(
                game: game,
                status: GameStatus(library: library, game: game),
              )
            }
          }
        } header: {
          Text("Games")
        } footer: {
          Text(
            """
            iHarbour doesn't include any game. Add a ROM of your own, and iHarbour recognizes \
            which game it belongs to and extracts that game's assets from it.
            """
          )
        }

        if !library.looseROMs.isEmpty {
          LooseROMsSection(
            roms: library.looseROMs,
            canImport: library.canImport,
            importROM: { romToImport = ROMToImport(url: $0.url) },
            delete: library.delete,
          )
        }
      }
      .navigationTitle("iHarbour")
      .navigationDestination(for: Game.self) { game in
        GameView(library: library, game: game)
      }
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("Add ROM", systemImage: "plus") {
            isImportingROM = true
          }
          .disabled(!library.canImport)
        }

        ToolbarItem(placement: .secondaryAction) {
          Button("Settings", systemImage: "gearshape") {
            isShowingSettings = true
          }
        }
      }
    }
    .sheet(isPresented: $isShowingSettings) {
      NavigationStack {
        AppSettingsView(touchControls: library.touchControls)
      }
    }
    .fileImporter(isPresented: $isImportingROM, allowedContentTypes: [.data]) { result in
      if case .success(let url) = result {
        romToImport = ROMToImport(url: url)
      }
    }
    .importsROMs($romToImport, into: library)
    .libraryAlerts(library, openGame: { path = [$0] })
    .onChange(of: scenePhase) {
      if scenePhase == .active {
        library.refresh()
      }
    }
    .task { await library.runLaunchArguments() }
  }
}

/// A ROM the player picked, and the game whose page they picked it from, if any.
struct ROMToImport: Equatable {
  let url: URL
  var expectedGame: Game?
}

extension View {
  /// Runs the import of `rom` whenever it's set, then clears it.
  func importsROMs(_ rom: Binding<ROMToImport?>, into library: Library) -> some View {
    task(id: rom.wrappedValue) {
      guard let romToImport = rom.wrappedValue else { return }
      await library.importROM(at: romToImport.url, expectedGame: romToImport.expectedGame)
      rom.wrappedValue = nil
    }
  }

  /// The library's problem and import-result alerts.
  func libraryAlerts(_ library: Library, openGame: @escaping (Game) -> Void) -> some View {
    alert(
      library.problem?.title ?? "",
      isPresented: Binding(
        get: { library.problem != nil },
        set: { if !$0 { library.problem = nil } },
      ),
      presenting: library.problem,
    ) { _ in
      Button("OK") {}
    } message: { problem in
      Text(problem.message)
    }
    .alert(
      "ROM Extracted",
      isPresented: Binding(
        get: { library.importResult != nil },
        set: { if !$0 { library.importResult = nil } },
      ),
      presenting: library.importResult,
    ) { result in
      Button("Open \(result.game.title)") { openGame(result.game) }
      Button("OK", role: .cancel) {}
    } message: { result in
      Text("\(result.description) is ready to play in \(result.game.title).")
    }
  }
}

/// How ready a game is, for its row and page.
enum GameStatus: Equatable {
  case notIncluded
  case needsROM
  case outdated
  case ready

  init(library: Library, game: Game) {
    if !library.isIncluded(game) {
      self = .notIncluded
    } else if library.isReady(game) {
      self = .ready
    } else if library.archives(of: game).contains(where: \.isMain) {
      self = .outdated
    } else {
      self = .needsROM
    }
  }

  var title: String {
    switch self {
    case .notIncluded: "Not in this build"
    case .needsROM: "Needs a ROM"
    case .outdated: "Game files outdated"
    case .ready: "Ready to play"
    }
  }

  var symbol: String {
    switch self {
    case .notIncluded: "minus.circle"
    case .needsROM: "arrow.down.circle"
    case .outdated: "exclamationmark.triangle.fill"
    case .ready: "checkmark.circle.fill"
    }
  }

  var color: Color {
    switch self {
    case .notIncluded: .secondary
    case .needsROM: .secondary
    case .outdated: .orange
    case .ready: .green
    }
  }
}

private struct GameRow: View {
  let game: Game
  let status: GameStatus

  var body: some View {
    HStack(spacing: 14) {
      GameArtwork(game: game, size: 64)
      VStack(alignment: .leading, spacing: 3) {
        Text(game.title)
          .font(.headline)
        Label(status.title, systemImage: status.symbol)
          .font(.caption.weight(.medium))
          .foregroundStyle(status.color)
          .labelStyle(.titleAndIcon)
      }
    }
    .padding(.vertical, 4)
    .opacity(status == .notIncluded ? 0.6 : 1)
    .accessibilityElement(children: .combine)
  }
}

private struct SessionEndedSection: View {
  let game: Game

  var body: some View {
    Section {
      Label {
        Text(
          """
          \(game.title) has quit. Games can run once per launch of iHarbour: to play again, \
          close iHarbour from the app switcher and open it again.
          """
        )
        .font(.callout)
      } icon: {
        Image(systemName: "arrow.clockwise.circle.fill")
          .foregroundStyle(.tint)
          .accessibilityHidden(true)
      }
    }
  }
}

private struct LooseROMsSection: View {
  let roms: [ROMFile]
  let canImport: Bool
  let importROM: (ROMFile) -> Void
  let delete: (ROMFile) -> Void

  var body: some View {
    Section {
      ForEach(roms) { rom in
        HStack {
          Label(rom.name, systemImage: "doc")
            .lineLimit(1)
            .truncationMode(.middle)
          Spacer()
          Button("Extract") { importROM(rom) }
            .buttonStyle(.bordered)
            .disabled(!canImport)
        }
        .swipeActions {
          Button("Delete", systemImage: "trash", role: .destructive) {
            delete(rom)
          }
        }
      }
    } header: {
      Text("ROMs in Files")
    } footer: {
      Text(
        "ROMs you put in On My iPhone › iHarbour, or in a game's folder there, in the Files app."
      )
    }
  }
}

/// The ROM being imported, and how far along it is.
struct ImportRow: View {
  let currentImport: Library.Import
  /// Read a few times a second: extractors report progress only by being asked.
  let progress: () -> Double?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      switch currentImport.phase {
      case .reading:
        Text("Reading \(currentImport.fileName)…")
          .lineLimit(1)
          .truncationMode(.middle)
        ProgressView()
      case .extracting(let game, let description):
        Text("Extracting \(description) for \(game.title)…")
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
          if let progress = progress() {
            ProgressView(value: progress)
          } else {
            ProgressView()
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        Text("This takes a minute or two. Keep iHarbour open.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }
}

#Preview("Library") {
  LibraryView(library: Library())
}
