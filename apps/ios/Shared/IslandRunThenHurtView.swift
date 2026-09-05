import SwiftUI

enum IslandTrackSegment {
  case full
  case firstHalf
  case secondHalf
}

/// Cena A/B/C — corrida com clip move @ 10fps (PC), handoff com histerese.
struct IslandRunThenHurtView: View {
  let skin: String
  var progress: Double
  var phase: IslandTiming.Phase
  var size: CGFloat = 36
  var segment: IslandTrackSegment = .full

  var body: some View {
    Group {
      if shouldShow {
        GeometryReader { geo in
          let travel = max(0, geo.size.width - size)
          dino
            .frame(width: size, height: size)
            .offset(x: travel * localX)
            .modifier(IslandPhaseStyle(phase: phase, progress: progress))
        }
        .frame(height: size + 4)
      } else {
        Color.clear.frame(height: size + 4)
      }
    }
    .accessibilityLabel("Dino na Dynamic Island")
  }

  private var runX: Double { IslandTiming.runX(at: progress) }

  private var localX: Double {
    switch segment {
    case .full:
      return runX
    case .firstHalf:
      return min(1, max(0, runX / 0.5))
    case .secondHalf:
      if phase != .run { return 1 }
      return min(1, max(0, (runX - 0.5) / 0.5))
    }
  }

  /// Histerese: um lado por vez, sem overlap piscando.
  private var shouldShow: Bool {
    switch segment {
    case .full:
      return phase != .done
    case .firstHalf:
      return phase == .run && runX < 0.5
    case .secondHalf:
      if phase == .hurt || phase == .fade { return true }
      if phase == .run { return runX >= 0.5 }
      return false
    }
  }

  private var spriteFrame: Int {
    switch phase {
    case .run:
      // ~10 fps ao longo do run
      return Int(IslandTiming.runX(at: progress) * IslandTiming.runDuration * 10) % 6
    case .hurt, .fade:
      return min(Int(progress * 8) % 4, 3)
    case .done:
      return 0
    }
  }

  @ViewBuilder
  private var dino: some View {
    #if canImport(UIKit)
    let clip: DinoClip = (phase == .run) ? .move : .hurt
    let key = DinoSpriteCatalog.sheetName(skin: skin, clip: clip)
    if let sheet = DinoSpriteCatalog.sheetImage(skin: skin, clip: clip) {
      Image(uiImage: DinoSpriteCatalog.frameImage(sheetKey: key, sheet: sheet, index: spriteFrame))
        .resizable()
        .interpolation(.none)
        .scaledToFit()
        .frame(width: size, height: size)
    } else {
      DinoStaticFrame(skin: skin, size: size)
    }
    #else
    DinoStaticFrame(skin: skin, size: size)
    #endif
  }
}

private struct IslandPhaseStyle: ViewModifier {
  let phase: IslandTiming.Phase
  let progress: Double

  func body(content: Content) -> some View {
    let hurtT = hurtAmount
    let fadeT = fadeAmount
    Group {
      switch phase {
      case .run:
        content
      case .hurt:
        content
          .colorMultiply(Color.red.opacity(0.55 + 0.45 * (1 - hurtT)))
          .scaleEffect(1.0 - 0.1 * hurtT)
      case .fade:
        content
          .colorMultiply(.red)
          .opacity(1.0 - fadeT)
          .scaleEffect(0.9 - 0.35 * fadeT)
      case .done:
        content.opacity(0)
      }
    }
  }

  private var hurtAmount: Double {
    let t = progress * IslandTiming.total
    let start = IslandTiming.runDuration
    return max(0, min(1, (t - start) / IslandTiming.hurtDuration))
  }

  private var fadeAmount: Double {
    let t = progress * IslandTiming.total
    let start = IslandTiming.runDuration + IslandTiming.hurtDuration
    return max(0, min(1, (t - start) / IslandTiming.fadeDuration))
  }
}
