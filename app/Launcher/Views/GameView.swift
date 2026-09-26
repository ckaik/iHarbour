import SwiftUI
import UniformTypeIdentifiers

/// One game's page: play it, manage its files, and reach its settings.
struct GameView: View {
  @Bindable var library: Library
  let game: Game

  @State private var isImportingROM = false
  @State private var romToImport: ROMToImport?

  var body: some View {
    let status = GameStatus(library: library, game: game)

    List {
      Section {
        PlayHeader(
          game: game,
          status: status,
          session: library.session,
          canPlay: library.canPlay(game),
          play: { library.play(game) },
        )
      }

      if status != .notIncluded {
        GameFilesSection(
          game: game,
          archives: library.archives(of: game),
          isOutdated: library.isOutdated,
          currentImport: library.currentImport,
          canImport: library.canImport,
          progress: { library.extractionProgress },
          importROM: { isImportingROM = true },
          delete: library.delete,
        )

        Section {
          if game.settings != nil {
            NavigationLink {
              GameSettingsScreen(game: game, isEditable: library.session.isIdle)
            } label: {
              Label("Settings", systemImage: "gearshape")
            }
          }

          if let folder = filesAppURL {
            Link(destination: folder) {
              Label("Show in Files", systemImage: "folder")
            }
          }
        } footer: {
          Text(game.menuDescription)
        }
      } else {
        Section {
          Text(
            """
            This build of iHarbour leaves \(game.title) out. Add it to HARBOUR_GAMES in \
            app/Config/Local.xcconfig, or remove that setting, and build again.
            """
          )
          .font(.callout)
        }
      }

      SupportedROMsSection(game: game)

      Section {
        Link(destination: game.website) {
          Label("\(game.title) on GitHub", systemImage: "safari")
        }
      }
    }
    .navigationTitle(game.title)
    .navigationBarTitleDisplayMode(.inline)
    .fileImporter(isPresented: $isImportingROM, allowedContentTypes: [.data]) { result in
      if case .success(let url) = result {
        romToImport = ROMToImport(url: url, expectedGame: game)
      }
    }
    .importsROMs($romToImport, into: library)
    // The library's alerts come from LibraryView, which stays in the hierarchy under this page.
    .task(
      id: ArchiveCheck(
        archives: library.archives(of: game),
        isImporting: library.currentImport != nil
      )
    ) {
      library.checkArchives(of: game)
    }
  }

  /// The game's folder in the Files app.
  private var filesAppURL: URL? {
    var components = URLComponents(url: game.dataDirectory, resolvingAgainstBaseURL: false)
    components?.scheme = "shareddocuments"
    return components?.url
  }
}

/// What makes a game page check its archives again: other files, or the end of an import.
private struct ArchiveCheck: Equatable {
  let archives: [InstalledArchive]
  let isImporting: Bool
}

private struct PlayHeader: View {
  let game: Game
  let status: GameStatus
  let session: Library.Session
  let canPlay: Bool
  let play: () -> Void

  var body: some View {
    VStack(spacing: 14) {
      GameArtwork(game: game, size: 112)
      Text(game.title)
        .font(.title2.bold())
      Button(action: play) {
        Label("Play", systemImage: "play.fill")
          .font(.title3.bold())
          .frame(maxWidth: .infinity)
          .padding(.vertical, 6)
      }
      .buttonStyle(.borderedProminent)
      .tint(game.tint)
      .disabled(!canPlay)
      if let message {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
  }

  private var message: String? {
    switch session {
    case .running(let running) where running == game:
      return "Playing."
    case .running(let running):
      return "\(running.title) is running."
    case .ended:
      return
        "A game has run since iHarbour started. Close iHarbour from the app switcher and open it again to play."
    case .idle:
      break
    }

    switch status {
    case .notIncluded: return "Not included in this build."
    case .needsROM: return "Add a ROM below to play."
    case .outdated: return "Extract the ROM again to play."
    case .ready: return nil
    }
  }
}

private struct GameFilesSection: View {
  let game: Game
  let archives: [InstalledArchive]
  let isOutdated: (InstalledArchive) -> Bool
  let currentImport: Library.Import?
  let canImport: Bool
  let progress: () -> Double?
  let importROM: () -> Void
  let delete: (InstalledArchive) -> Void

  var body: some View {
    Section {
      ForEach(archives) { archive in
        ArchiveRow(archive: archive, isOutdated: isOutdated(archive))
          .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) {
              delete(archive)
            }
            .disabled(!canImport)
          }
      }

      if let currentImport {
        ImportRow(currentImport: currentImport, progress: progress)
      }

      Button("Add a ROM…", systemImage: "square.and.arrow.down", action: importROM)
        .disabled(!canImport)
    } header: {
      Text("Game Files")
    } footer: {
      Text(
        """
        \(game.title) needs its assets extracted from a ROM of the original game that you own. \
        Extracting takes a minute or two, and the ROM isn't needed afterwards.
        """
      )
    }
  }
}

private struct ArchiveRow: View {
  let archive: InstalledArchive
  let isOutdated: Bool

  var body: some View {
    LabeledContent {
      Text(archive.byteCount, format: .byteCount(style: .file))
    } label: {
      Label {
        Text(archive.title)
        if isOutdated {
          Text("From an older version of the game. Extract the ROM again.")
        } else if let date = archive.modificationDate {
          Text(
            "\(archive.url.lastPathComponent), extracted \(date, format: .dateTime.day().month().year())"
          )
        }
      } icon: {
        if isOutdated {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .accessibilityHidden(true)
        } else {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .accessibilityHidden(true)
        }
      }
    }
  }
}

private struct SupportedROMsSection: View {
  let game: Game

  var body: some View {
    Section {
      DisclosureGroup("Supported ROMs") {
        ForEach(game.roms, id: \.sha1) { rom in
          VStack(alignment: .leading, spacing: 2) {
            Text(rom.title)
            Text("SHA-1 \(rom.sha1)")
              .font(.caption2.monospaced())
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
        }
      }
    } footer: {
      Text(".z64, .n64, and .v64 files all work.")
    }
  }
}

#Preview {
  NavigationStack {
    GameView(library: Library(), game: Game.all[0])
  }
}
