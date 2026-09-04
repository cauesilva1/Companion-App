import SwiftUI

extension View {
  /// Compat iOS 16 widget + iOS 17 containerBackground.
  @ViewBuilder
  func companionWidgetBackground() -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      self.containerBackground(.fill.tertiary, for: .widget)
    } else {
      self.background(Color(.secondarySystemBackground))
    }
  }
}
