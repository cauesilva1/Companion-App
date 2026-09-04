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
  let entry: CompanionEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(entry.snapshot.moodEmoji).font(.largeTitle)
        VStack(alignment: .leading) {
          Text(entry.snapshot.name).font(.headline)
          Text(entry.snapshot.mood).font(.caption).foregroundStyle(.secondary)
        }
      }
      Text(entry.snapshot.moodText)
        .font(.caption)
        .lineLimit(2)
      Label("Energia \(entry.snapshot.energyPercent)%", systemImage: "bolt.fill")
        .font(.caption2)
      Label("Afeto \(entry.snapshot.affectionPercent)%", systemImage: "heart.fill")
        .font(.caption2)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }
}
