import UIKit

/// The on-screen controller, drawn over the game.
///
/// UIKit rather than SwiftUI: each finger is tracked on its own, a thumb can slide from one face
/// button onto the next, and touches that land between controls must fall through to the game's
/// window underneath, which turns them into clicks for the in-game menu. SwiftUI gestures offer
/// none of the three.
final class TouchControlsView: UIView {
  private let configuration: TouchControlsConfiguration

  /// Hides the game controls, for example while a hardware controller or the in-game menu is in
  /// use. The menu button stays.
  var hidesGameControls = false {
    didSet {
      guard hidesGameControls != oldValue else { return }

      if hidesGameControls {
        release(Set(assignments.filter(\.value.isGameControl).keys))
      }

      applyConfiguration()
    }
  }

  private var controlViews: [TouchControl: TouchControlButtonView] = [:]
  private let stickKnob = UIView()
  private var controlFrames: [TouchControl: CGRect] = [:]

  private var assignments: [UITouch: TouchControl] = [:]
  private var pressedControls: Set<TouchControl> = []

  private let haptics = UIImpactFeedbackGenerator(style: .light)
  private let engine: GameEngine

  init(configuration: TouchControlsConfiguration, engine: GameEngine) {
    self.configuration = configuration
    self.engine = engine
    super.init(frame: .zero)

    isMultipleTouchEnabled = true
    backgroundColor = .clear
    // VoiceOver passes touches straight through, as a game controller needs.
    isAccessibilityElement = true
    accessibilityLabel = "Game controller"
    accessibilityTraits = .allowsDirectInteraction

    for control in TouchControl.allCases {
      let view = TouchControlButtonView(control: control)
      controlViews[control] = view
      addSubview(view)
    }

    stickKnob.isUserInteractionEnabled = false
    stickKnob.backgroundColor = UIColor(white: 0.9, alpha: 0.9)
    addSubview(stickKnob)

    applyConfiguration()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("TouchControlsView is only created in code")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    controlFrames = Self.frames(in: bounds, safeArea: safeAreaInsets)
    for (control, view) in controlViews {
      view.frame = controlFrames[control] ?? .zero
    }

    // Layout passes happen mid-game (rotating between the two landscapes, safe area changes); a
    // finger may be holding the stick then, and its position must survive.
    if !assignments.values.contains(.stick) {
      centerStick()
    }
  }

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    control(at: point) != nil
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    for touch in touches {
      let location = touch.location(in: self)
      guard let control = control(at: location) else { continue }
      assignments[touch] = control
      switch control {
      case .menu: engine.toggleMenu()
      case .stick: moveStick(to: location)
      default: break
      }
    }

    syncPressedControls()
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    for touch in touches {
      guard let control = assignments[touch] else { continue }
      let location = touch.location(in: self)
      if control == .stick {
        moveStick(to: location)
      } else if control.takesSlidingThumbs,
        let target = self.control(at: location),
        target != control,
        target.takesSlidingThumbs
      {
        assignments[touch] = target
      }
    }

    syncPressedControls()
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    release(touches)
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    release(touches)
  }

  /// Lets go of everything, so no input stays stuck when the controls go away.
  func releaseAllTouches() {
    release(Set(assignments.keys))
  }

  private func release(_ touches: Set<UITouch>) {
    var releasesStick = false
    for touch in touches {
      let control = assignments.removeValue(forKey: touch)
      releasesStick = releasesStick || control == .stick
    }

    // Another finger may still hold the stick.
    if releasesStick, !assignments.values.contains(.stick) {
      centerStick()
    }

    syncPressedControls()
  }

  private var visibleControls: [TouchControl] {
    let showsGameControls = configuration.showsControls && !hidesGameControls
    return TouchControl.allCases.filter { control in
      guard control.isGameControl else { return true }
      return showsGameControls && (!control.isDPad || configuration.showsDPad)
    }
  }

  private func applyConfiguration() {
    let visible = Set(visibleControls)
    for (control, view) in controlViews {
      view.isHidden = !visible.contains(control)
    }
    stickKnob.isHidden = !visible.contains(.stick)

    alpha = configuration.opacity

    if configuration.playsHaptics {
      haptics.prepare()
    }
  }

  /// The visible control under `point`, allowing some slop around each so a thumb doesn't have
  /// to be exact. Where slop areas overlap, the closest control wins.
  private func control(at point: CGPoint) -> TouchControl? {
    let slop = min(bounds.width, bounds.height) * 0.03

    return
      visibleControls
      .compactMap { control -> (control: TouchControl, distance: CGFloat)? in
        guard let frame = controlFrames[control] else { return nil }
        let allowance = control == .stick ? frame.width * 0.35 : slop
        let distance = Self.distance(from: point, to: frame)
        return distance <= allowance ? (control, distance) : nil
      }
      .min { $0.distance < $1.distance }?
      .control
  }

  private func syncPressedControls() {
    let pressed = Set(assignments.values)
    let newlyPressed = pressed.subtracting(pressedControls)
    let released = pressedControls.subtracting(pressed)
    pressedControls = pressed

    for control in released {
      send(control, isPressed: false)
    }
    for control in newlyPressed {
      send(control, isPressed: true)
    }

    if configuration.playsHaptics, newlyPressed.contains(where: { $0 != .stick }) {
      haptics.impactOccurred()
    }

    // The C buttons share the right stick, so it's the sum of all that are held.
    if newlyPressed.union(released).contains(where: { $0.rightStickOffset != nil }) {
      let offset = pressed.compactMap(\.rightStickOffset)
        .reduce(CGVector.zero) {
          CGVector(dx: $0.dx + $1.dx, dy: $0.dy + $1.dy)
        }

      engine.setAxis(HarbourAxisRightX, to: offset.dx)
      engine.setAxis(HarbourAxisRightY, to: offset.dy)
    }

    for (control, view) in controlViews {
      view.isPressed = pressed.contains(control)
    }
  }

  private func send(_ control: TouchControl, isPressed: Bool) {
    if let button = control.button {
      engine.setButton(button, isPressed: isPressed)
    }
    if let trigger = control.trigger {
      engine.setAxis(trigger, to: isPressed ? 1 : 0)
    }
  }

  private func moveStick(to location: CGPoint) {
    guard let base = controlFrames[.stick] else { return }

    let radius = base.width / 2
    var offset = CGVector(dx: location.x - base.midX, dy: location.y - base.midY)
    let length = hypot(offset.dx, offset.dy)
    if length > radius {
      offset = CGVector(dx: offset.dx / length * radius, dy: offset.dy / length * radius)
    }

    stickKnob.center = CGPoint(x: base.midX + offset.dx, y: base.midY + offset.dy)
    engine.setAxis(HarbourAxisLeftX, to: offset.dx / radius)
    engine.setAxis(HarbourAxisLeftY, to: offset.dy / radius)
  }

  private func centerStick() {
    guard let base = controlFrames[.stick] else { return }

    let knobSize = base.width * 0.45
    stickKnob.bounds = CGRect(x: 0, y: 0, width: knobSize, height: knobSize)
    stickKnob.layer.cornerRadius = knobSize / 2
    stickKnob.center = CGPoint(x: base.midX, y: base.midY)

    engine.setAxis(HarbourAxisLeftX, to: 0)
    engine.setAxis(HarbourAxisLeftY, to: 0)
  }

  private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
    let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
    let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
    return hypot(dx, dy)
  }

  /// Where each control goes: the stick, Z and the D-pad under the left thumb, the face buttons and
  /// R under the right, roughly where they sit on the original controller. Sizes scale with the
  /// shorter side of the screen, up to a cap so they stay thumb-sized on an iPad.
  private static func frames(in bounds: CGRect, safeArea: UIEdgeInsets) -> [TouchControl: CGRect] {
    let unit = min(min(bounds.width, bounds.height) / 100, 4.5)
    let area = bounds.inset(by: safeArea).insetBy(dx: 3 * unit, dy: 3 * unit)

    func circle(x: CGFloat, y: CGFloat, diameter: CGFloat) -> CGRect {
      CGRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter)
    }

    func pill(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
      CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
    }

    let stick = circle(x: area.minX + 18 * unit, y: area.maxY - 18 * unit, diameter: 36 * unit)
    let a = circle(x: area.maxX - 9 * unit, y: area.maxY - 12 * unit, diameter: 17 * unit)

    let cCenter = CGPoint(x: area.maxX - 16 * unit, y: area.maxY - 45 * unit)
    let cSpacing = 11.5 * unit
    let cDiameter = 11 * unit

    let dCenter = CGPoint(x: stick.maxX + 16 * unit, y: area.maxY - 12 * unit)
    let dSpacing = 8.5 * unit
    let dDiameter = 8.5 * unit

    return [
      .stick: stick,
      .z: pill(x: stick.midX, y: stick.minY - 11 * unit, width: 22 * unit, height: 10 * unit),
      .l: pill(
        x: area.minX + 9 * unit,
        y: area.minY + 5 * unit,
        width: 18 * unit,
        height: 9 * unit
      ),
      .r: pill(
        x: area.maxX - 11 * unit,
        y: area.minY + 5 * unit,
        width: 22 * unit,
        height: 10 * unit
      ),
      .a: a,
      .b: circle(x: a.midX - 18 * unit, y: a.midY - 7 * unit, diameter: 14 * unit),
      .cUp: circle(x: cCenter.x, y: cCenter.y - cSpacing, diameter: cDiameter),
      .cDown: circle(x: cCenter.x, y: cCenter.y + cSpacing, diameter: cDiameter),
      .cLeft: circle(x: cCenter.x - cSpacing, y: cCenter.y, diameter: cDiameter),
      .cRight: circle(x: cCenter.x + cSpacing, y: cCenter.y, diameter: cDiameter),
      .dUp: circle(x: dCenter.x, y: dCenter.y - dSpacing, diameter: dDiameter),
      .dDown: circle(x: dCenter.x, y: dCenter.y + dSpacing, diameter: dDiameter),
      .dLeft: circle(x: dCenter.x - dSpacing, y: dCenter.y, diameter: dDiameter),
      .dRight: circle(x: dCenter.x + dSpacing, y: dCenter.y, diameter: dDiameter),
      .start: circle(x: area.midX, y: area.maxY - 5 * unit, diameter: 11 * unit),
      .menu: pill(x: area.midX, y: area.minY + 4 * unit, width: 20 * unit, height: 8 * unit),
    ]
  }
}

/// How a single control looks. Touches go to the ``TouchControlsView`` that owns it.
private final class TouchControlButtonView: UIView {
  var isPressed = false {
    didSet { updateColors() }
  }

  private let control: TouchControl
  private let label = UILabel()

  init(control: TouchControl) {
    self.control = control
    super.init(frame: .zero)

    isUserInteractionEnabled = false
    layer.borderWidth = 2

    label.text = control.title
    label.textColor = .white
    label.textAlignment = .center
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.5
    addSubview(label)

    updateColors()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("TouchControlButtonView is only created in code")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    layer.cornerRadius = min(bounds.width, bounds.height) / 2
    label.frame = bounds.insetBy(dx: bounds.width * 0.12, dy: 0)
    label.font = .systemFont(ofSize: min(bounds.width, bounds.height) * 0.42, weight: .heavy)
  }

  private func updateColors() {
    let tint = control.tint
    layer.borderColor = tint.cgColor
    backgroundColor = tint.withAlphaComponent(isPressed ? 0.85 : 0.3)
  }
}
