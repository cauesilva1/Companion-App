import SwiftUI
import WidgetKit

/// Mesmo visual do `SkyBackground` do app (gradiente + plate + véu).
private struct SkyWidgetFill: View {
  let sky: SkyPeriod

  var body: some View {
    ZStack {
      sky.gradient
      Image(sky.imageName)
        .resizable()
        .scaledToFill()
        .opacity(sky.preferredArtOpacity)
      LinearGradient(
        colors: [
          Color.white.opacity(0.05),
          Color.white.opacity(0.18),
          Color(red: 0.95, green: 0.97, blue: 1.0).opacity(0.45),
          Color(red: 0.94, green: 0.96, blue: 0.99).opacity(0.70),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    }
  }
}

extension View {
  @ViewBuilder
  func companionMockupWidgetBackground(sky: SkyPeriod) -> some View {
    companionWidgetBackground(sky: sky)
  }

  @ViewBuilder
  func companionMockupWidgetBackground() -> some View {
    companionWidgetBackground(sky: SkyPeriod.resolved())
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

  @ViewBuilder
  func companionExpandIntoMargins() -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      self.padding(-16)
    } else {
      self
    }
  }

  @ViewBuilder
  func companionAccessoryBackground() -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      self.containerBackground(for: .widget) {
        AccessoryWidgetBackground()
      }
    } else {
      self.background(AccessoryWidgetBackground())
    }
  }
}
