import SwiftUI

@main
struct HarbourApp: App {
  @State private var library = Library()

  var body: some Scene {
    WindowGroup {
      LibraryView(library: library)
    }
  }
}
