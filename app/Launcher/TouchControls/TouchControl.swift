import UIKit

/// One control of the on-screen controller, and what it drives on the game's side.
///
/// Games see a standard gamepad and maps it with libultraship's default gamepad bindings, so each
/// original input goes to the gamepad input those bindings expect: Z and R are the triggers, the C
/// buttons are the right stick.
enum TouchControl: CaseIterable, Hashable {
  case stick
  case a
  case b
  case z
  case l
  case r
  case start
  case cUp
  case cDown
  case cLeft
  case cRight
  case dUp
  case dDown
  case dLeft
  case dRight
  case menu

  /// A gamepad button this control holds down while pressed.
  var button: HarbourButton? {
    switch self {
    case .a: HarbourButtonA
    case .b: HarbourButtonB
    case .l: HarbourButtonLeftShoulder
    case .start: HarbourButtonStart
    case .dUp: HarbourButtonDPadUp
    case .dDown: HarbourButtonDPadDown
    case .dLeft: HarbourButtonDPadLeft
    case .dRight: HarbourButtonDPadRight
    default: nil
    }
  }

  /// A trigger this control pulls all the way while pressed.
  var trigger: HarbourAxis? {
    switch self {
    case .z: HarbourAxisTriggerLeft
    case .r: HarbourAxisTriggerRight
    default: nil
    }
  }

  /// How far this control pushes the right stick while pressed.
  var rightStickOffset: CGVector? {
    switch self {
    case .cUp: CGVector(dx: 0, dy: -1)
    case .cDown: CGVector(dx: 0, dy: 1)
    case .cLeft: CGVector(dx: -1, dy: 0)
    case .cRight: CGVector(dx: 1, dy: 0)
    default: nil
    }
  }

  /// Whether a thumb sliding onto this control from another face button presses it, the way
  /// players rock between A, B and the C buttons.
  var takesSlidingThumbs: Bool {
    switch self {
    case .a, .b, .cUp, .cDown, .cLeft, .cRight: true
    default: false
    }
  }

  /// Controls that only matter while playing, as opposed to the menu button.
  var isGameControl: Bool { self != .menu }

  /// The D-pad, which few of the games use and so is optional.
  var isDPad: Bool {
    switch self {
    case .dUp, .dDown, .dLeft, .dRight: true
    default: false
    }
  }

  var title: String {
    switch self {
    case .stick: ""
    case .a: "A"
    case .b: "B"
    case .z: "Z"
    case .l: "L"
    case .r: "R"
    case .start: "START"
    case .cUp: "▲"
    case .cDown: "▼"
    case .cLeft: "◀"
    case .cRight: "▶"
    case .dUp: "↑"
    case .dDown: "↓"
    case .dLeft: "←"
    case .dRight: "→"
    case .menu: "MENU"
    }
  }

  /// The original controller's colors, so the buttons are easy to find without reading them.
  var tint: UIColor {
    switch self {
    case .a: UIColor(red: 0.20, green: 0.40, blue: 0.95, alpha: 1)
    case .b: UIColor(red: 0.15, green: 0.70, blue: 0.30, alpha: 1)
    case .start: UIColor(red: 0.85, green: 0.20, blue: 0.20, alpha: 1)
    case .cUp, .cDown, .cLeft, .cRight: UIColor(red: 0.95, green: 0.78, blue: 0.10, alpha: 1)
    default: UIColor(white: 0.55, alpha: 1)
    }
  }
}
