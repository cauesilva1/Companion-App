import WidgetKit
import SwiftUI

/// Lock screen — avatar estático + afeto (sem animação de frames).
struct CompanionLockWidget: Widget {
  let kind = "CompanionLockWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: CompanionLockProvider()) { entry in
      CompanionLockView(entry: entry)
        // iOS 17+ exige containerBackground — sem isso o gallery mostra "!" quebrado.
        .companionMockupWidgetBackground(sky: entry.sky)
        .widgetURL(URL(string: "companion://feed?source=lock"))
    }
    .configurationDisplayName("Companion Lock")
    .description("Avatar e afeto.")
    .supportedFamilies([
      .accessoryCircular,
      .accessoryRectangular,
      .accessoryInline,
    ])
  }
}

struct CompanionLockProvider: TimelineProvider {
  func placeholder(in context: Context) -> CompanionEntry {
    CompanionWidgetTimeline.staticEntry(snapshot: CompanionWidgetTimeline.previewSnapshot)
  }

  func getSnapshot(in context: Context, completion: @escaping (CompanionEntry) -> Void) {
    if context.isPreview {
      completion(placeholder(in: context))
      return
    }
    completion(
      CompanionWidgetTimeline.staticEntry(snapshot: CompanionWidgetTimeline.resolvedSnapshot())
    )
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<CompanionEntry>) -> Void) {
    // Uma entrada só, frame 0 — sem mexer o sprite.
    let entry = CompanionWidgetTimeline.staticEntry(snapshot: CompanionWidgetTimeline.resolvedSnapshot())
    completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(300))))
  }
}

struct CompanionLockView: View {
  @Environment(\.widgetFamily) private var family
  let entry: CompanionEntry

  var body: some View {
    switch family {
    case .accessoryCircular:
      circular
    case .accessoryInline:
      Text("\(entry.snapshot.name) · ♥\(entry.snapshot.affectionPercent)%")
        .lineLimit(1)
    default:
      rectangular
    }
  }

  private var circular: some View {
    ZStack {
      AccessoryWidgetBackground()
      VStack(spacing: 0) {
        // DinoAvatar = frame único do asset (não anima).
        DinoAvatar(skin: entry.snapshot.skin, size: 26)
        Text("♥\(entry.snapshot.affectionPercent)")
          .font(.system(size: 10, weight: .bold, design: .rounded))
          .minimumScaleFactor(0.75)
      }
    }
  }

  private var rectangular: some View {
    HStack(spacing: 10) {
      DinoAvatar(skin: entry.snapshot.skin, size: 40)
      VStack(alignment: .leading, spacing: 4) {
        Text(entry.snapshot.name)
          .font(.headline)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        Text("♥ Afeto \(entry.snapshot.affectionPercent)%")
          .font(.caption.weight(.semibold))
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }
}
