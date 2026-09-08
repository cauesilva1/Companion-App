import WidgetKit
import SwiftUI

/// Widget compacto para a tela de bloqueio (iOS 16+).
struct CompanionLockWidget: Widget {
  let kind = "CompanionLockWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: CompanionProvider()) { entry in
      CompanionLockView(entry: entry)
        .companionMockupWidgetBackground()
        .widgetURL(URL(string: "companion://feed"))
    }
    .configurationDisplayName("Companion Lock")
    .description("Avatar, energia e última fala.")
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
        VStack(spacing: 0) {
          WidgetDinoFrame(skin: entry.snapshot.skin, frameIndex: entry.frameIndex, size: 26)
          Text("\(entry.snapshot.energyPercent)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
        }
      }
    case .accessoryInline:
      Text("\(entry.snapshot.name) · \(entry.lastLine)")
    default:
      HStack(spacing: 8) {
        WidgetDinoFrame(skin: entry.snapshot.skin, frameIndex: entry.frameIndex, size: 34)
        VStack(alignment: .leading, spacing: 2) {
          Text(entry.snapshot.name)
            .font(.headline)
          Text("⚡\(entry.snapshot.energyPercent)  ♥\(entry.snapshot.affectionPercent)")
            .font(.caption2.monospacedDigit())
          Text(entry.lastLine)
            .font(.caption2)
            .lineLimit(2)
        }
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
  }
}
