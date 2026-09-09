import WidgetKit
import SwiftUI

struct CompanionEntry: TimelineEntry {
  let date: Date
  let snapshot: CompanionSnapshot
  let frameIndex: Int
  let lastLine: String
}

enum CompanionWidgetTimeline {
  static let frameInterval: TimeInterval = 0.2
  static let cycleSeconds: TimeInterval = 4.0

  static func entries(now: Date = Date(), snapshot: CompanionSnapshot) -> [CompanionEntry] {
    #if canImport(UIKit)
    let sheet = DinoSpriteCatalog.sheetImage(skin: snapshot.skin, clip: .idle)
    let frameCount = max(1, sheet.map { DinoSpriteCatalog.frameCount(for: $0) } ?? 3)
    #else
    let frameCount = 3
    #endif
    let line = shortBlurb(for: snapshot, maxChars: 180)
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

  static func staticEntry(
    now: Date = Date(),
    snapshot: CompanionSnapshot,
    maxChars: Int = 180
  ) -> CompanionEntry {
    CompanionEntry(
      date: now,
      snapshot: snapshot,
      frameIndex: 0,
      lastLine: shortBlurb(for: snapshot, maxChars: maxChars)
    )
  }

  static func shortBlurb(for snapshot: CompanionSnapshot, maxChars: Int) -> String {
    let full = latestLine(for: snapshot)
    // Grava o texto COMPLETO — truncar só na UI do widget (senão a conversa herda o "…").
    if !WidgetSpeechStore.isGenericStatusLine(full) {
      WidgetSpeechStore.saveDisplayLine(full)
    }
    // Soft-cap alto: o lineLimit do SwiftUI usa a altura do widget de verdade.
    return truncate(full, maxChars: max(maxChars, 180))
  }

  static func latestLine(for snapshot: CompanionSnapshot) -> String {
    let candidates: [String?] = [
      snapshot.morningThought,
      LifeModeStore.pendingMorningThought,
      ThoughtFeedStore.latestLine(),
      WidgetSpeechStore.load()?.idleLine,
      WidgetSpeechStore.displayLine(),
      snapshot.moodText,
    ]
    var firstGeneric: String?
    var firstTruncated: String?
    for raw in candidates {
      let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !t.isEmpty else { continue }
      if t == "Oi! Vamos brincar?" { continue }
      if t.localizedCaseInsensitiveContains("crescer") { continue }
      if t.localizedCaseInsensitiveContains("evoluir") { continue }
      if WidgetSpeechStore.isGenericStatusLine(t) {
        if firstGeneric == nil { firstGeneric = t }
        continue
      }
      // Prefere frase completa; "…" é só visual do widget antigo pinado.
      if t.hasSuffix("…") || t.hasSuffix("...") {
        if let full = WidgetSpeechStore.expandTruncated(t) {
          return full
        }
        if firstTruncated == nil { firstTruncated = t }
        continue
      }
      return t
    }
    if let pinned = WidgetSpeechStore.displayLine() {
      return WidgetSpeechStore.expandTruncated(pinned) ?? pinned
    }
    return firstTruncated ?? firstGeneric ?? "\(snapshot.name) por aqui"
  }

  static func truncate(_ text: String, maxChars: Int) -> String {
    let t = text
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard t.count > maxChars else { return t }
    let end = t.index(t.startIndex, offsetBy: maxChars)
    var slice = String(t[..<end])
    if let sp = slice.lastIndex(of: " "), sp > slice.startIndex {
      slice = String(slice[..<sp])
    }
    return slice.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
  }

  static func resolvedSnapshot() -> CompanionSnapshot {
    CompanionSnapshotStore.load() ?? .demo
  }

  static var previewSnapshot: CompanionSnapshot {
    CompanionSnapshot(
      id: "preview",
      name: "Jaozinho",
      mood: "HAPPY",
      moodText: "De boa no sofá.",
      energy: 64,
      affection: 82,
      skin: "dino-mono",
      archetype: "zoeiro",
      updatedAt: Date(),
      growthStage: "baby",
      createdAt: Date(),
      presenceStatus: "present",
      decayFrozen: false,
      lifeMode: "indoor",
      gamingStatus: nil,
      mediaHint: nil,
      morningThought: nil,
      activeTitle: nil,
      titleKey: nil,
      equippedTitleKey: nil
    )
  }
}

struct CompanionProvider: TimelineProvider {
  func placeholder(in context: Context) -> CompanionEntry {
    CompanionWidgetTimeline.staticEntry(snapshot: CompanionWidgetTimeline.previewSnapshot, maxChars: 56)
  }

  func getSnapshot(in context: Context, completion: @escaping (CompanionEntry) -> Void) {
    if context.isPreview {
      completion(placeholder(in: context))
      return
    }
    completion(
      CompanionWidgetTimeline.staticEntry(
        snapshot: CompanionWidgetTimeline.resolvedSnapshot(),
        maxChars: 180
      )
    )
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<CompanionEntry>) -> Void) {
    let snap = CompanionWidgetTimeline.resolvedSnapshot()
    let now = Date()
    let entries = CompanionWidgetTimeline.entries(now: now, snapshot: snap)
    completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(CompanionWidgetTimeline.cycleSeconds))))
  }
}

struct CompanionHomeWidget: Widget {
  let kind = "CompanionHomeWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: CompanionProvider()) { entry in
      CompanionHomeView(entry: entry)
        .companionExpandIntoMargins()
        .companionMockupWidgetBackground()
        .widgetURL(URL(string: "companion://feed?source=widget"))
    }
    .configurationDisplayName("Companion")
    .description("Seu companion e o pensamento do momento.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct CompanionHomeView: View {
  @Environment(\.widgetFamily) private var family
  let entry: CompanionEntry

  private var lightChrome: Bool { SkyPeriod.current().prefersLightChrome }
  private var titleColor: Color { lightChrome ? Color.white : Color(red: 0.12, green: 0.18, blue: 0.32) }
  private var quoteColor: Color { lightChrome ? Color.white.opacity(0.95) : Color(red: 0.16, green: 0.22, blue: 0.36) }
  private var mutedColor: Color { lightChrome ? Color.white.opacity(0.7) : Color(red: 0.34, green: 0.4, blue: 0.52) }
  private var trackFill: Color {
    lightChrome ? Color.white.opacity(0.22) : Color.black.opacity(0.1)
  }
  private var panel: Color {
    lightChrome ? Color.black.opacity(0.2) : Color.white.opacity(0.42)
  }

  var body: some View {
    Group {
      if family == .systemSmall { small } else { medium }
    }
  }

  private var small: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .center, spacing: 8) {
        WidgetDinoFrame(skin: entry.snapshot.skin, frameIndex: entry.frameIndex, size: 44)

        VStack(alignment: .leading, spacing: 3) {
          Text(entry.snapshot.name)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(titleColor)
            .lineLimit(1)
            .minimumScaleFactor(0.75)

          HStack(spacing: 8) {
            HStack(spacing: 2) {
              Image(systemName: "bolt.fill")
                .foregroundStyle(Color.yellow.opacity(0.95))
              Text("\(entry.snapshot.energyPercent)")
                .foregroundStyle(titleColor)
            }
            HStack(spacing: 2) {
              Image(systemName: "heart.fill")
                .foregroundStyle(Color.pink.opacity(0.9))
              Text("\(entry.snapshot.affectionPercent)")
                .foregroundStyle(titleColor)
            }
          }
          .font(.caption2.monospacedDigit().weight(.bold))
        }
        Spacer(minLength: 0)
      }

      Text(entry.lastLine)
        .font(.caption.weight(.medium))
        .foregroundStyle(quoteColor)
        .lineLimit(7)
        .minimumScaleFactor(0.78)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .layoutPriority(1)
    }
    .padding(10)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  /// Medium: dino em destaque + fala como citação (sem barras grossas poluídas).
  private var medium: some View {
    HStack(alignment: .center, spacing: 14) {
      WidgetDinoFrame(skin: entry.snapshot.skin, frameIndex: entry.frameIndex, size: 96)

      VStack(alignment: .leading, spacing: 8) {
        Text(entry.snapshot.name)
          .font(.title3.bold())
          .foregroundStyle(titleColor)
          .lineLimit(1)

        HStack(spacing: 10) {
          statChip(
            icon: "bolt.fill",
            value: entry.snapshot.energyPercent,
            color: Color.yellow.opacity(0.95)
          )
          statChip(
            icon: "heart.fill",
            value: entry.snapshot.affectionPercent,
            color: Color.pink.opacity(0.9)
          )
        }

        Text(entry.lastLine)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(quoteColor)
          .lineLimit(3)
          .minimumScaleFactor(0.85)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }

  private func statChip(icon: String, value: Int, color: Color) -> some View {
    HStack(spacing: 4) {
      Image(systemName: icon)
        .font(.caption2.weight(.bold))
        .foregroundStyle(color)
      Text("\(value)%")
        .font(.caption.monospacedDigit().weight(.bold))
        .foregroundStyle(titleColor)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(Capsule().fill(panel))
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
      DinoAvatar(skin: skin, size: size)
    }
    #else
    DinoAvatar(skin: skin, size: size)
    #endif
  }
}
