import WidgetKit
import SwiftUI

struct CompanionEntry: TimelineEntry {
  let date: Date
  let snapshot: CompanionSnapshot
}

struct CompanionProvider: TimelineProvider {
  func placeholder(in context: Context) -> CompanionEntry {
    CompanionEntry(date: Date(), snapshot: .demo)
  }

  func getSnapshot(in context: Context, completion: @escaping (CompanionEntry) -> Void) {
    let snap = CompanionSnapshotStore.load() ?? .demo
    completion(CompanionEntry(date: Date(), snapshot: snap))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<CompanionEntry>) -> Void) {
    let snap = CompanionSnapshotStore.load() ?? .demo
    let entry = CompanionEntry(date: Date(), snapshot: snap)
    let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
    completion(Timeline(entries: [entry], policy: .after(next)))
  }
}

struct CompanionHomeWidget: Widget {
  let kind = "CompanionHomeWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: CompanionProvider()) { entry in
      CompanionHomeView(entry: entry)
        .companionWidgetBackground()
    }
    .configurationDisplayName("Companion")
    .description("Humor e energia do seu dino.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct CompanionHomeView: View {
  @Environment(\.widgetFamily) private var family
  let entry: CompanionEntry

  var body: some View {
    HStack(spacing: 10) {
      DinoAvatar(skin: entry.snapshot.skin, size: family == .systemSmall ? 44 : 64)
      VStack(alignment: .leading, spacing: 4) {
        Text(entry.snapshot.name).font(.headline)
        Text("\(entry.snapshot.moodEmoji) \(entry.snapshot.moodText)")
          .font(.caption)
          .lineLimit(2)
        if family != .systemSmall {
          Label("Energia \(entry.snapshot.energyPercent)%", systemImage: "bolt.fill")
            .font(.caption2)
          Label("Afeto \(entry.snapshot.affectionPercent)%", systemImage: "heart.fill")
            .font(.caption2)
        } else {
          Text("⚡\(entry.snapshot.energyPercent)%")
            .font(.caption2.monospacedDigit())
        }
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }
}
