import GameController
import OSLog
import UIKit

/// A window above the game's that holds the on-screen controller.
///
/// SDL gives the game a window of its own, so the controls can't live inside the game's view
/// hierarchy. They float above it instead, and touches that miss every control fall through to
/// the game's window.
final class TouchControlsWindow: UIWindow {
  private let controlsView: TouchControlsView
  private let hidesWithHardwareController: Bool
  private let engine: GameEngine

  private var menuPoll: Timer?
  private var observers: [any NSObjectProtocol] = []

  init(windowScene: UIWindowScene, configuration: TouchControlsConfiguration, engine: GameEngine) {
    controlsView = TouchControlsView(configuration: configuration, engine: engine)
    hidesWithHardwareController = configuration.hidesWithHardwareController
    self.engine = engine
    super.init(windowScene: windowScene)

    windowLevel = .normal + 1
    backgroundColor = .clear
    rootViewController = TouchControlsViewController(controlsView: controlsView)

    for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
      let observer = NotificationCenter.default.addObserver(
        forName: name,
        object: nil,
        queue: .main,
      ) { [weak self] _ in
        // Delivered on the main queue, as requested above.
        MainActor.assumeIsolated { self?.updateHiddenControls() }
      }
      observers.append(observer)
    }

    // The game doesn't announce when its menu opens or closes, so look a few times a second.
    menuPoll = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
      // Scheduled on the main run loop, which the game keeps turning while it runs.
      MainActor.assumeIsolated { self?.updateHiddenControls() }
    }

    updateHiddenControls()
    isHidden = false
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("TouchControlsWindow is only created in code")
  }

  /// Takes the controls off screen for good, letting go of anything still held.
  func tearDown() {
    menuPoll?.invalidate()
    menuPoll = nil
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
    controlsView.releaseAllTouches()
    isHidden = true
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let view = super.hitTest(point, with: event)
    // Only the window itself was hit, so no control was: the game gets the touch.
    return view === self ? nil : view
  }

  private func updateHiddenControls() {
    let hasHardwareController = !GCController.controllers().isEmpty
    let isMenuOpen = engine.isMenuOpen
    let hides = isMenuOpen || (hidesWithHardwareController && hasHardwareController)

    if hides != controlsView.hidesGameControls {
      Logger.touchControls.info(
        "Game controls \(hides ? "hidden" : "shown") (menu open: \(isMenuOpen), controllers: \(GCController.controllers().map { $0.vendorName ?? "?" }))"
      )
    }
    controlsView.hidesGameControls = hides
  }
}

private final class TouchControlsViewController: UIViewController {
  private let controlsView: TouchControlsView

  init(controlsView: TouchControlsView) {
    self.controlsView = controlsView
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("TouchControlsViewController is only created in code")
  }

  override func loadView() {
    view = controlsView
  }

  override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
  override var prefersStatusBarHidden: Bool { true }
  override var prefersHomeIndicatorAutoHidden: Bool { true }
}

extension Logger {
  static let touchControls = Logger(subsystem: "org.iharbour", category: "TouchControls")
}
