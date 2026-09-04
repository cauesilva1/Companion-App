import WidgetKit
import SwiftUI

/// Widget compacto para a tela de bloqueio (iOS 16+).
struct CompanionLockWidget: Widget {
  let kind = "CompanionLockWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: CompanionProvider()) { entry in
      CompanionLockView(entry: entry)
        .companionWidgetBackground()
    }
    .configurationDisplayName("Companion Lock")
    .description("Seu dino na tela de bloqueio.")
    .supportedFamilies([
      .accessoryCircular,
      .accessoryRectangular,
      .accessoryInline,
    ])
  }
}

struct CompanionLockView: View {
  @Environment(\.widgetFamily) private var family
  let entry: CompanionEntry

  var body: some View {
    switch family {
    case .accessoryCircular:
      ZStack {
        AccessoryWidgetBackground()
        DinoAvatar(skin: entry.snapshot.skin, size: 28)
      }
    case .accessoryInline:
      Text("\(entry.snapshot.name) · \(entry.snapshot.energyPercent)%")
    default:
      HStack(spacing: 8) {
        DinoAvatar(skin: entry.snapshot.skin, size: 36)
        VStack(alignment: .leading, spacing: 2) {
          Text(entry.snapshot.name)
            .font(.headline)
          Text(entry.snapshot.moodText)
            .font(.caption2)
            .lineLimit(2)
          Text("⚡\(entry.snapshot.energyPercent) ❤️\(entry.snapshot.affectionPercent)")
            .font(.caption2)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
  }
}
