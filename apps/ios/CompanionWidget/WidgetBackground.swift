import SwiftUI

private struct SkyWidgetFill: View {
  let sky: SkyPeriod

  var body: some View {
    ZStack {
      sky.gradient
      Image(sky.imageName)
        .resizable()
        .scaledToFill()
        .opacity(0.55)
    }
  }
}

extension View {
  /// Fundo de céu por hora do dia (widgets).
  @ViewBuilder
  func companionMockupWidgetBackground() -> some View {
    companionWidgetBackground(sky: .current())
  }

  @ViewBuilder
  func companionWidgetBackground(sky: SkyPeriod = .current()) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      self.containerBackground(for: .widget) {
        SkyWidgetFill(sky: sky)
      }
    } else {
      self.background(SkyWidgetFill(sky: sky))
    }
  }
}
