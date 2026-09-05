import WidgetKit
import SwiftUI

struct CompanionEntry: TimelineEntry {
  let date: Date
  let snapshot: CompanionSnapshot
  let frameIndex: Int
}

enum CompanionWidgetTimeline {
  /// ~14 fps em ciclos curtos — WidgetKit não permite 60fps contínuo.
  static let frameInterval: TimeInterval = 0.07
  static let cycleSeconds: TimeInterval = 4.2


  static func entries(now: Date = Date(), snapshot: CompanionSnapshot) -> [CompanionEntry] {
    #if canImport(UIKit)
    let sheet = DinoSpriteCatalog.sheetImage(skin: snapshot.skin, clip: .idle)
    let frameCount = max(1, sheet.map { DinoSpriteCatalog.frameCount(for: $0) } ?? 3)
    #else
    let frameCount = 3
    #endif
    let steps = Int(cycleSeconds / frameInterval)
    return (0..<steps).map { i in
      CompanionEntry(
        date: now.addingTimeInterval(Double(i) * frameInterval),
        snapshot: snapshot,
        frameIndex: i % frameCount
      )
    }
  }
}

struct CompanionProvider: TimelineProvider {
  func placeholder(in context: Context) -> CompanionEntry {
    CompanionEntry(date: Date(), snapshot: .demo, frameIndex: 0)
  }

  func getSnapshot(in context: Context, completion: @escaping (CompanionEntry) -> Void) {
    let snap = CompanionSnapshotStore.load() ?? .demo
    completion(CompanionEntry(date: Date(), snapshot: snap, frameIndex: 0))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<CompanionEntry>) -> Void) {
    let snap = CompanionSnapshotStore.load() ?? .demo
    let now = Date()
    let entries = CompanionWidgetTimeline.entries(now: now, snapshot: snap)
    let refresh = now.addingTimeInterval(CompanionWidgetTimeline.cycleSeconds)
    completion(Timeline(entries: entries, policy: .after(refresh)))
  }
}

struct CompanionHomeWidget: Widget {
  let kind = "CompanionHomeWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: CompanionProvider()) { entry in
      CompanionHomeView(entry: entry)
        .companionMockupWidgetBackground()
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
    Group {
      if family == .systemSmall {
        small
      } else {
        medium
      }
    }
  }

  private var teaser: String {
    LocalVoice.widgetTeaser(
      name: entry.snapshot.name,
      mood: entry.snapshot.mood,
      energy: entry.snapshot.energyPercent
    )
  }

  private var small: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        WidgetDinoFrame(skin: entry.snapshot.skin, frameIndex: entry.frameIndex, size: 44)
        Spacer(minLength: 0)
        Text("⚡\(entry.snapshot.energyPercent)%")
          .font(.caption.weight(.bold).monospacedDigit())
          .foregroundStyle(CompanionTheme.title)
      }
      Text(teaser)
        .font(.caption.weight(.semibold))
        .foregroundStyle(CompanionTheme.title)
        .lineLimit(3)
        .minimumScaleFactor(0.85)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .padding(6)
  }

  private var medium: some View {
    HStack(spacing: 14) {
      WidgetDinoFrame(skin: entry.snapshot.skin, frameIndex: entry.frameIndex, size: 72)
      VStack(alignment: .leading, spacing: 6) {
        Text(entry.snapshot.name)
          .font(.title3.bold())
          .foregroundStyle(CompanionTheme.title)
        Text(teaser)
          .font(.caption)
          .lineLimit(2)
          .foregroundStyle(CompanionTheme.subtitle)
        ProgressView(value: Double(entry.snapshot.energyPercent), total: 100)
          .tint(CompanionTheme.energy)
        HStack {
          Text("⚡ \(entry.snapshot.energyPercent)%")
          Text("♥ \(entry.snapshot.affectionPercent)%")
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(CompanionTheme.subtitle)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .padding(8)
  }
}

struct WidgetDinoFrame: View {
  let skin: String
  let frameIndex: Int
  var size: CGFloat = 48

  var body: some View {
    #if canImport(UIKit)
    if let sheet = DinoSpriteCatalog.sheetImage(skin: skin, clip: .idle) {
      let key = DinoSpriteCatalog.sheetName(skin: skin, clip: .idle)
      Image(uiImage: DinoSpriteCatalog.frameImage(sheetKey: key, sheet: sheet, index: frameIndex))
        .resizable()
        .interpolation(.none)
        .scaledToFit()
        .frame(width: size, height: size)
    } else {
      DinoStaticFrame(skin: skin, size: size)
    }
    #else
    DinoStaticFrame(skin: skin, size: size)
    #endif
  }
}
