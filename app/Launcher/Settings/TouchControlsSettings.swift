import Foundation
import Observation

/// The on-screen controller's settings, shared by all games. The controller belongs to the
/// launcher, so they live in `UserDefaults`.
@Observable
final class TouchControlsSettings {
  private enum Key {
    static let showsControls = "TouchControls.Shows"
    static let hidesWithHardwareController = "TouchControls.HidesWithController"
    static let opacity = "TouchControls.Opacity"
    static let playsHaptics = "TouchControls.Haptics"
    static let showsDPad = "TouchControls.ShowsDPad"
  }

  var configuration: TouchControlsConfiguration {
    didSet { save() }
  }

  @ObservationIgnored private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults

    let fallback = TouchControlsConfiguration()
    defaults.register(defaults: [
      Key.showsControls: fallback.showsControls,
      Key.hidesWithHardwareController: fallback.hidesWithHardwareController,
      Key.opacity: fallback.opacity,
      Key.playsHaptics: fallback.playsHaptics,
      Key.showsDPad: fallback.showsDPad,
    ])

    configuration = TouchControlsConfiguration(
      showsControls: defaults.bool(forKey: Key.showsControls),
      hidesWithHardwareController: defaults.bool(forKey: Key.hidesWithHardwareController),
      opacity: defaults.double(forKey: Key.opacity),
      playsHaptics: defaults.bool(forKey: Key.playsHaptics),
      showsDPad: defaults.bool(forKey: Key.showsDPad),
    )
  }

  private func save() {
    defaults.set(configuration.showsControls, forKey: Key.showsControls)
    defaults.set(configuration.hidesWithHardwareController, forKey: Key.hidesWithHardwareController)
    defaults.set(configuration.opacity, forKey: Key.opacity)
    defaults.set(configuration.playsHaptics, forKey: Key.playsHaptics)
    defaults.set(configuration.showsDPad, forKey: Key.showsDPad)
  }
}
