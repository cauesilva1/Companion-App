import SwiftUI
import WidgetKit

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

  /// iOS 17+ aplica margem interna ~16pt — cancela pra usar o retângulo todo.
  @ViewBuilder
  func companionExpandIntoMargins() -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      self.padding(-16)
    } else {
      self
    }
  }

  /// Fundo correto pra accessory (lock) — sem céu colorido.
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
