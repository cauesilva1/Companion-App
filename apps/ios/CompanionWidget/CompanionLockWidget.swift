import WidgetKit
import SwiftUI

/// Widget compacto para a tela de bloqueio (iOS 16+).
struct CompanionLockWidget: Widget {
  let kind = "CompanionLockWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: CompanionProvider()) { entry in
      CompanionLockView(entry: entry)
        .companionMockupWidgetBackground()
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

  private var teaser: String { entry.statusLine }

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
      Text("\(entry.snapshot.name) · \(teaser)")
    default:
      HStack(spacing: 8) {
        WidgetDinoFrame(skin: entry.snapshot.skin, frameIndex: entry.frameIndex, size: 34)
        VStack(alignment: .leading, spacing: 2) {
          Text(entry.snapshot.name)
            .font(.headline)
          Text(teaser)
            .font(.caption2)
            .lineLimit(2)
        }
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
  }
}