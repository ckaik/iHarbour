/// How the on-screen controller looks and behaves while the game runs.
nonisolated struct TouchControlsConfiguration: Equatable, Sendable {
  /// Whether the on-screen controller is shown at all. The menu button always is, since it's the
  /// only way into the in-game menu without a keyboard.
  var showsControls = true
  /// Hides the on-screen controller while a hardware controller is connected.
  var hidesWithHardwareController = true
  var opacity = 0.6
  var playsHaptics = true
  /// Shows a D-pad next to the stick. Few of the games use one.
  var showsDPad = false
}
