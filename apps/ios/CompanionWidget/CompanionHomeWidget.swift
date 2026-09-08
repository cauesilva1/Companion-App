import WidgetKit
import SwiftUI

struct CompanionEntry: TimelineEntry {
  let date: Date
  let snapshot: CompanionSnapshot
  let frameIndex: Int
  let lastLine: String
}

enum CompanionWidgetTimeline {
  static let frameInterval: TimeInterval = 0.15
  static let cycleSeconds: TimeInterval = 4.0

  static func entries(now: Date = Date(), snapshot: CompanionSnapshot) -> [CompanionEntry] {
    #if canImport(UIKit)
    let sheet = DinoSpriteCatalog.sheetImage(skin: snapshot.skin, clip: .idle)
    let frameCount = max(1, sheet.map { DinoSpriteCatalog.frameCount(for: $0) } ?? 3)
    #else
    let frameCount = 3
    #endif
    let line = latestLine(for: snapshot)
    let steps = Int(cycleSeconds / frameInterval)
    return (0..<steps).map { i in
      CompanionEntry(
        date: now.addingTimeInterval(Double(i) * frameInterval),
        snapshot: snapshot,
        frameIndex: i % frameCount,
        lastLine: line
      )
    }
  }

  static func latestLine(for snapshot: CompanionSnapshot) -> String {
    if let thought = ThoughtFeedStore.latestLine(), !thought.isEmpty {
      return thought
    }
    if let speech = WidgetSpeechStore.load(),
       let idle = speech.idleLine?.trimmingCharacters(in: .whitespacesAndNewlines),
       !idle.isEmpty {
      return idle
    }
    let t = snapshot.moodText.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? "\(snapshot.name) por aqui" : t
  }
}

struct CompanionProvider: TimelineProvider {
  func placeholder(in context: Context) -> CompanionEntry {
    CompanionEntry(date: Date(), snapshot: .demo, frameIndex: 0, lastLine: "Oi!")
  }

  func getSnapshot(in context: Context, completion: @escaping (CompanionEntry) -> Void) {
    let snap = CompanionSnapshotStore.load() ?? .demo
    completion(
      CompanionEntry(
        date: Date(),
        snapshot: snap,
        frameIndex: 0,
        lastLine: CompanionWidgetTimeline.latestLine(for: snap)
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
        .widgetURL(URL(string: "companion://feed"))
    }
    .configurationDisplayName("Companion")
    .description("Avatar, energia e a última fala.")
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
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        WidgetDinoFrame(skin: entry.snapshot.skin, frameIndex: entry.frameIndex, size: 40)
        Text(entry.snapshot.name)
          .font(.subheadline.weight(.bold))
          .foregroundStyle(titleColor)
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      miniBar(value: entry.snapshot.energyPercent, color: Color.yellow.opacity(0.95))
      miniBar(value: entry.snapshot.affectionPercent, color: Color.pink.opacity(0.9))
      Text(entry.lastLine)
        .font(.caption2.weight(.medium))
        .foregroundStyle(bodyColor)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
    }
    .padding(10)
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
      VStack(alignment: .leading, spacing: 6) {
        Text(entry.snapshot.name)
          .font(.title3.bold())
          .foregroundStyle(titleColor)
        labeledBar(title: "Energia", value: entry.snapshot.energyPercent, color: Color.yellow.opacity(0.95))
        labeledBar(title: "Afeto", value: entry.snapshot.affectionPercent, color: Color.pink.opacity(0.9))
        Text(entry.lastLine)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(bodyColor)
          .lineLimit(2)
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(panelFill)
    )
    .padding(4)
  }

  private func miniBar(value: Int, color: Color) -> some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(Color.white.opacity(lightChrome ? 0.2 : 0.25))
        Capsule()
          .fill(color)
          .frame(width: geo.size.width * CGFloat(max(0, min(100, value))) / 100)
      }
    }
    .frame(height: 5)
  }

  private func labeledBar(title: String, value: Int, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("\(title) \(value)%")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(bodyColor)
      miniBar(value: value, color: color)
    }
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
