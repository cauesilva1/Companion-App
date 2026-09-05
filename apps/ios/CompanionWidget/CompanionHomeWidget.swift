import WidgetKit
import SwiftUI

struct CompanionEntry: TimelineEntry {
  let date: Date
  let snapshot: CompanionSnapshot
  let frameIndex: Int
  /// Texto estável por ciclo (não sorteia a cada frame).
  let statusLine: String
  let needLine: String
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
    let (status, need) = lines(for: snapshot)
    let steps = Int(cycleSeconds / frameInterval)
    return (0..<steps).map { i in
      CompanionEntry(
        date: now.addingTimeInterval(Double(i) * frameInterval),
        snapshot: snapshot,
        frameIndex: i % frameCount,
        statusLine: status,
        needLine: need
      )
    }
  }

  static func lines(for snapshot: CompanionSnapshot) -> (String, String) {
    if let speech = WidgetSpeechStore.load(), speech.hasFreshMusic {
      let status = speech.trackLine ?? stableStatus(snapshot)
      let need = speech.comment?.trimmingCharacters(in: .whitespacesAndNewlines)
      if let need, !need.isEmpty {
        return (status, need)
      }
      return (status, needLine(snapshot))
    }
    if let speech = WidgetSpeechStore.load(),
       let idle = speech.idleLine?.trimmingCharacters(in: .whitespacesAndNewlines),
       !idle.isEmpty,
       Date().timeIntervalSince(speech.updatedAt) < 60 * 60 {
      return (idle, needLine(snapshot))
    }
    return (stableStatus(snapshot), needLine(snapshot))
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

  static func needLine(_ snapshot: CompanionSnapshot) -> String {
    LocalVoice.widgetNeedLine(
      mood: snapshot.mood,
      energy: snapshot.energyPercent,
      affection: snapshot.affectionPercent
    )
  }
}

struct CompanionProvider: TimelineProvider {
  func placeholder(in context: Context) -> CompanionEntry {
    CompanionEntry(date: Date(), snapshot: .demo, frameIndex: 0, statusLine: "Oi!", needLine: "de boa por aqui")
  }

  func getSnapshot(in context: Context, completion: @escaping (CompanionEntry) -> Void) {
    let snap = CompanionSnapshotStore.load() ?? .demo
    let (status, need) = CompanionWidgetTimeline.lines(for: snap)
    completion(
      CompanionEntry(
        date: Date(),
        snapshot: snap,
        frameIndex: 0,
        statusLine: status,
        needLine: need
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
    .description("Humor do seu dino.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct CompanionHomeView: View {
  @Environment(\.widgetFamily) private var family
  let entry: CompanionEntry

  private var lightChrome: Bool { SkyPeriod.current().prefersLightChrome }
  private var titleColor: Color { lightChrome ? Color.white : Color(red: 0.12, green: 0.18, blue: 0.32) }
  private var bodyColor: Color { lightChrome ? Color.white.opacity(0.9) : Color(red: 0.22, green: 0.28, blue: 0.42) }
  private var panelFill: Color {
    lightChrome ? Color.black.opacity(0.38) : Color.white.opacity(0.72)
  }

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
    HStack(alignment: .center, spacing: 8) {
      WidgetDinoFrame(skin: entry.snapshot.skin, frameIndex: entry.frameIndex, size: 44)
      VStack(alignment: .leading, spacing: 2) {
        Text(entry.snapshot.name)
          .font(.subheadline.weight(.bold))
          .foregroundStyle(titleColor)
          .lineLimit(1)
        Text(entry.statusLine)
          .font(.caption.weight(.medium))
          .foregroundStyle(bodyColor)
          .lineLimit(2)
          .minimumScaleFactor(0.8)
        Text(entry.needLine)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(lightChrome ? Color.white.opacity(0.78) : CompanionTheme.play)
          .lineLimit(2)
          .minimumScaleFactor(0.8)
      }
      Spacer(minLength: 0)
    }
    .padding(8)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(panelFill)
    )
    .padding(4)
  }

  private var medium: some View {
    HStack(spacing: 12) {
      WidgetDinoFrame(skin: entry.snapshot.skin, frameIndex: entry.frameIndex, size: 72)
      VStack(alignment: .leading, spacing: 5) {
        Text(entry.snapshot.name)
          .font(.title3.bold())
          .foregroundStyle(titleColor)
        Text(entry.statusLine)
          .font(.subheadline.weight(.medium))
          .lineLimit(2)
          .foregroundStyle(bodyColor)
        Text(entry.needLine)
          .font(.caption.weight(.semibold))
          .foregroundStyle(lightChrome ? Color.white.opacity(0.78) : CompanionTheme.play)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(10)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(panelFill)
    )
    .padding(4)
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
