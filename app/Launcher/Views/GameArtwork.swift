import SwiftUI

/// A game's artwork: the port's own logo on a tile in the game's color.
struct GameArtwork: View {
  let game: Game
  let size: CGFloat

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
    Image(game.imageName)
      .resizable()
      .scaledToFit()
      .padding(size * 0.06)
      .frame(width: size, height: size)
      .background(game.tint.gradient, in: shape)
      .clipShape(shape)
      .overlay(shape.strokeBorder(.white.opacity(0.15), lineWidth: 1))
      .accessibilityHidden(true)
  }
}

#Preview {
  HStack {
    ForEach(Game.all) { game in
      GameArtwork(game: game, size: 64)
    }
  }
  .padding()
}
