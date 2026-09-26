import SwiftUI

/// Settings that apply to every game: the on-screen controller, and where things are.
struct AppSettingsView: View {
  @Bindable var touchControls: TouchControlsSettings
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    Form {
      Section {
        Toggle("Show On-Screen Controller", isOn: $touchControls.configuration.showsControls)

        Toggle(
          "Hide with Game Controller",
          isOn: $touchControls.configuration.hidesWithHardwareController,
        )
        .disabled(!touchControls.configuration.showsControls)

        Toggle("Show D-Pad", isOn: $touchControls.configuration.showsDPad)
          .disabled(!touchControls.configuration.showsControls)

        LabeledContent("Opacity") {
          Slider(value: $touchControls.configuration.opacity, in: 0.2 ... 1)
            .frame(maxWidth: 220)
        }
        .disabled(!touchControls.configuration.showsControls)

        Toggle("Haptic Feedback", isOn: $touchControls.configuration.playsHaptics)
          .disabled(!touchControls.configuration.showsControls)
      } header: {
        Text("On-Screen Controller")
      } footer: {
        Text(
          """
          Game controllers, keyboards, and mice work too. The MENU button stays on screen either \
          way, and opens the game's own menu.
          """
        )
      }

      Section {
        LabeledContent("Version", value: Self.appVersion)
      } footer: {
        Text(
          """
          Each game keeps its files (extracted archives, settings, saves, mods) in a folder of \
          its own in On My iPhone › iHarbour, in the Files app.
          """
        )
      }
    }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") { dismiss() }
      }
    }
  }

  private static var appVersion: String {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "?"
    let build = info?["CFBundleVersion"] as? String ?? "?"
    return "\(version) (\(build))"
  }
}

#Preview {
  NavigationStack {
    AppSettingsView(touchControls: TouchControlsSettings())
  }
}
