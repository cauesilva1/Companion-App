import SwiftUI

/// Corre até a borda da Island → animação de dano → some.
/// Funciona com o app fechado (TimelineView + startedAt).
struct IslandRunThenHurtView: View {
  let skin: String
  let startedAt: Date
  var size: CGFloat = 36

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
      let elapsed = context.date.timeIntervalSince(startedAt)
      GeometryReader { geo in
        let travel = max(0, geo.size.width - size)
        content(elapsed: elapsed, travel: travel)
      }
    }
    .frame(height: size + 4)
    .accessibilityLabel("Dino na Dynamic Island")
  }

  @ViewBuilder
  private func content(elapsed: TimeInterval, travel: CGFloat) -> some View {
    if elapsed < IslandTiming.runDuration {
      let t = elapsed / IslandTiming.runDuration
      let eased = t * t * (3 - 2 * t)
      DinoAvatar(skin: skin, size: size)
        .offset(x: eased * travel)
    } else if elapsed < IslandTiming.runDuration + IslandTiming.hurtDuration {
      let hurtT = (elapsed - IslandTiming.runDuration) / IslandTiming.hurtDuration
      let shake = sin(hurtT * .pi * 8) * 4
      DinoAvatar(skin: skin, size: size)
        .colorMultiply(Color.red.opacity(0.55 + 0.45 * (1 - hurtT)))
        .offset(x: travel + shake)
        .scaleEffect(1.0 - 0.12 * hurtT)
        .rotationEffect(.degrees(Double(shake)))
    } else if elapsed < IslandTiming.total {
      let fadeT = (elapsed - IslandTiming.runDuration - IslandTiming.hurtDuration) / IslandTiming.fadeDuration
      DinoAvatar(skin: skin, size: size)
        .colorMultiply(.red)
        .offset(x: travel)
        .scaleEffect(0.88 - 0.4 * fadeT)
        .opacity(1.0 - fadeT)
    } else {
      Color.clear
    }
  }
}
