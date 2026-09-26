import SwiftUI

/// Loads a game's settings from its config file when shown.
struct GameSettingsScreen: View {
  let game: Game
  let isEditable: Bool

  @State private var settings: GameSettings?

  var body: some View {
    Group {
      if let settings {
        GameSettingsView(settings: settings, isEditable: isEditable)
      } else {
        ProgressView()
      }
    }
    .onAppear {
      if settings == nil {
        settings = GameSettings(game: game)
      }
    }
  }
}

/// A game's settings worth choosing before it starts. The in-game menu has the rest.
struct GameSettingsView: View {
  @Bindable var settings: GameSettings
  let isEditable: Bool

  @State private var isConfirmingReset = false

  var body: some View {
    Form {
      GraphicsSection(settings: settings)

      if settings.names.masterVolume != nil || settings.names.menuScale != nil {
        Section("Sound and Menu") {
          if settings.names.masterVolume != nil {
            LabeledContent("Master Volume") {
              Slider(value: masterVolume, in: 0 ... 100, step: 5)
                .frame(maxWidth: 220)
            }
          }

          if settings.names.menuScale != nil {
            Picker("Menu Size", selection: $settings.menuSize) {
              ForEach(GameSettings.MenuSize.allCases) { size in
                Text(size.title).tag(size)
              }
            }
          }
        }
      }

      Section {
        Button("Reset \(settings.game.title) Settings", role: .destructive) {
          isConfirmingReset = true
        }
      } footer: {
        if !isEditable {
          Text(
            "A game has run since iHarbour started. Changes take effect the next time it starts."
          )
        }
      }
    }
    .navigationTitle("Settings")
    .confirmationDialog(
      "Reset the settings on this screen to the game's defaults?",
      isPresented: $isConfirmingReset,
      titleVisibility: .visible,
    ) {
      Button("Reset", role: .destructive, action: settings.reset)
    }
  }

  private var masterVolume: Binding<Double> {
    Binding(
      get: { Double(settings.masterVolume) },
      set: { settings.masterVolume = Int($0) },
    )
  }
}

private struct GraphicsSection: View {
  @Bindable var settings: GameSettings

  var body: some View {
    let names = settings.names

    Section {
      if names.internalResolution != nil {
        LabeledContent("Resolution") {
          HStack {
            Slider(value: $settings.internalResolution, in: 0.5 ... 2, step: 0.25)
            Text(settings.internalResolution, format: .percent.precision(.fractionLength(0)))
              .monospacedDigit()
              .frame(minWidth: 48, alignment: .trailing)
          }
          .frame(maxWidth: 260)
        }
      }

      if names.msaa != nil {
        Picker("Anti-Aliasing", selection: $settings.msaa) {
          Text("Off").tag(1)
          ForEach([2, 4, 8], id: \.self) { samples in
            Text("\(samples)× MSAA").tag(samples)
          }
        }
      }

      if names.textureFilter != nil {
        Picker("Texture Filtering", selection: $settings.textureFilter) {
          ForEach(GameSettings.TextureFilter.allCases) { filter in
            Text(filter.title).tag(filter)
          }
        }
      }

      if names.matchesRefreshRate != nil {
        Toggle("Match Display Refresh Rate", isOn: $settings.matchesRefreshRate)
      }

      if names.frameRate != nil {
        Picker("Frame Rate", selection: $settings.frameRate) {
          ForEach(frameRates, id: \.self) { rate in
            if rate == settings.game.originalFrameRate {
              Text("Original (\(rate) fps)").tag(rate)
            } else {
              Text("\(rate) fps").tag(rate)
            }
          }
        }
        .disabled(names.matchesRefreshRate != nil && settings.matchesRefreshRate)
      }
    } header: {
      Text("Graphics")
    } footer: {
      Text(
        """
        Resolution is relative to the screen's. Frame rates above the original \
        \(settings.game.originalFrameRate) fps are interpolated and cost more battery.
        """
      )
    }
  }

  private var maximumFrameRate: Int {
    Library.activeWindowScene?.screen.maximumFramesPerSecond ?? 60
  }

  private var frameRates: [Int] {
    let rates = [settings.game.originalFrameRate, 30, 60, 120]
      .filter { $0 <= maximumFrameRate && $0 >= settings.game.originalFrameRate }
    let unique = Array(Set(rates)).sorted()

    // Keep a rate chosen elsewhere, such as in the in-game menu, selectable.
    return unique.contains(settings.frameRate) ? unique : (unique + [settings.frameRate]).sorted()
  }
}
