import WidgetKit
import SwiftUI

struct CompanionEntry: TimelineEntry {
  let date: Date
  let snapshot: CompanionSnapshot
  let frameIndex: Int
  /// Texto estável por ciclo (não sorteia a cada frame).
  let statusLine: String
}

enum CompanionWidgetTimeline {
  /// ~10 fps — animação do dino; texto fixo no ciclo.
  static let frameInterval: TimeInterval = 0.1
  static let cycleSeconds: TimeInterval = 5.0

  static func entries(now: Date = Date(), snapshot: CompanionSnapshot) -> [CompanionEntry] {
    #if canImport(UIKit)
    let sheet = DinoSpriteCatalog.sheetImage(skin: snapshot.skin, clip: .idle)
    let frameCount = max(1, sheet.map { DinoSpriteCatalog.frameCount(for: $0) } ?? 3)
    #else
    let frameCount = 3
    #endif
    let status = stableStatus(snapshot)
    let steps = Int(cycleSeconds / frameInterval)
    return (0..<steps).map { i in
      CompanionEntry(
        date: now.addingTimeInterval(Double(i) * frameInterval),
        snapshot: snapshot,
        frameIndex: i % frameCount,
        statusLine: status
      )
    }
  }

  static func stableStatus(_ snapshot: CompanionSnapshot) -> String {
    let mood = snapshot.mood.uppercased()
    switch mood {
    case "EXCITED": return "\(snapshot.name) tá empolgado"
    case "HAPPY": return "\(snapshot.name) tá bem"
    case "CONTENT": return "\(snapshot.name) de boa"
    case "BORED": return "\(snapshot.name) meio sem graça"
    case "SLEEPY": return "\(snapshot.name) com sono"
    case "SAD": return "\(snapshot.name) precisando de você"
    case "LONELY": return "\(snapshot.name) sentindo falta"
    default:
      let t = snapshot.moodText.trimmingCharacters(in: .whitespacesAndNewlines)
      return t.isEmpty ? "\(snapshot.name) por aqui" : t
    }
  }
}

struct CompanionProvider: TimelineProvider {
  func placeholder(in context: Context) -> CompanionEntry {
    CompanionEntry(date: Date(), snapshot: .demo, frameIndex: 0, statusLine: "Oi!")
  }

  func getSnapshot(in context: Context, completion: @escaping (CompanionEntry) -> Void) {
    let snap = CompanionSnapshotStore.load() ?? .demo
    completion(
      CompanionEntry(
        date: Date(),
        snapshot: snap,
        frameIndex: 0,
        statusLine: CompanionWidgetTimeline.stableStatus(snap)
      )
    )
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

  private var small: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top) {
        WidgetDinoFrame(skin: entry.snapshot.skin, frameIndex: entry.frameIndex, size: 44)
        Spacer(minLength: 0)
        Text("⚡\(entry.snapshot.energyPercent)%")
          .font(.caption.weight(.bold).monospacedDigit())
          .foregroundStyle(Color.black.opacity(0.85))
      }
      Text(entry.snapshot.name)
        .font(.subheadline.weight(.bold))
        .foregroundStyle(Color.black.opacity(0.9))
        .lineLimit(1)
      Text(entry.statusLine)
        .font(.caption.weight(.medium))
        .foregroundStyle(Color.black.opacity(0.7))
        .lineLimit(2)
        .minimumScaleFactor(0.85)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .padding(8)
  }

  private var medium: some View {
    HStack(spacing: 14) {
      WidgetDinoFrame(skin: entry.snapshot.skin, frameIndex: entry.frameIndex, size: 72)
      VStack(alignment: .leading, spacing: 6) {
        Text(entry.snapshot.name)
          .font(.title3.bold())
          .foregroundStyle(Color.black.opacity(0.92))
        Text(entry.statusLine)
          .font(.subheadline.weight(.medium))
          .lineLimit(2)
          .foregroundStyle(Color.black.opacity(0.72))
        ProgressView(value: Double(entry.snapshot.energyPercent), total: 100)
          .tint(CompanionTheme.energy)
        HStack(spacing: 12) {
          Label("\(entry.snapshot.energyPercent)%", systemImage: "bolt.fill")
          Label("\(entry.snapshot.affectionPercent)%", systemImage: "heart.fill")
        }
        .font(.caption.weight(.semibold).monospacedDigit())
        .foregroundStyle(Color.black.opacity(0.65))
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .padding(10)
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
