import Foundation
import WidgetKit

/// Payload do widget (App Group): música+comentário ou fala idle.
struct WidgetSpeechPayload: Codable, Equatable {
  var name: String
  var idleLine: String?
  var trackTitle: String?
  var trackArtist: String?
  var comment: String?
  var updatedAt: Date

  var hasFreshMusic: Bool {
    guard trackTitle != nil, !trackTitle!.isEmpty else { return false }
    return Date().timeIntervalSince(updatedAt) < 20 * 60
  }

  var trackLine: String? {
    guard let title = trackTitle, !title.isEmpty else { return nil }
    if let artist = trackArtist, !artist.isEmpty {
      return "♪ \(title) — \(artist)"
    }
    return "♪ \(title)"
  }
}

enum WidgetSpeechStore {
  private static let key = "companion.widgetSpeech.v1"
  private static let displayLineKey = "companion.widgetDisplayLine.v1"

  /// Status genérico do MoodEngine — não deve substituir a fala do widget.
  static func isGenericStatusLine(_ text: String) -> Bool {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return true }
    if t == "Oi! Vamos brincar?" { return true }
    let lower = t.lowercased()
    if lower.hasSuffix(" por aqui") { return true }
    if lower.range(
      of: #"está (feliz|tranquilo|empolgado|entediado|com sono|triste|sentindo sua falta)$"#,
      options: .regularExpression
    ) != nil {
      return true
    }
    return false
  }

  static func save(_ payload: WidgetSpeechPayload) {
    guard let data = try? JSONEncoder().encode(payload) else { return }
    CompanionAppGroup.defaults.set(data, forKey: key)
    UserDefaults.standard.set(data, forKey: key)
  }

  static func load() -> WidgetSpeechPayload? {
    if let data = CompanionAppGroup.defaults.data(forKey: key),
       let p = try? JSONDecoder().decode(WidgetSpeechPayload.self, from: data) {
      return p
    }
    if let data = UserDefaults.standard.data(forKey: key),
       let p = try? JSONDecoder().decode(WidgetSpeechPayload.self, from: data) {
      return p
    }
    return nil
  }

  static func saveMusic(title: String, artist: String?, comment: String, name: String) {
    save(
      WidgetSpeechPayload(
        name: name,
        idleLine: comment,
        trackTitle: title,
        trackArtist: artist,
        comment: comment,
        updatedAt: Date()
      )
    )
    if !isGenericStatusLine(comment) {
      saveDisplayLine(comment)
    }
  }

  static func saveIdle(line: String, name: String) {
    // Não deixa status genérico apagar a fala boa do widget.
    if isGenericStatusLine(line) { return }
    if line.hasSuffix("…") || line.hasSuffix("...") { return }

    var current = load()
    if let cur = current, cur.hasFreshMusic {
      current = WidgetSpeechPayload(
        name: name,
        idleLine: line,
        trackTitle: cur.trackTitle,
        trackArtist: cur.trackArtist,
        comment: cur.comment,
        updatedAt: cur.updatedAt
      )
      if let current { save(current) }
      saveDisplayLine(line)
      return
    }
    save(
      WidgetSpeechPayload(
        name: name,
        idleLine: line,
        trackTitle: nil,
        trackArtist: nil,
        comment: nil,
        updatedAt: Date()
      )
    )
    saveDisplayLine(line)
  }

  /// Linha fixa do widget — sobrevive a sync/cloud que limpa o thought feed.
  static func saveDisplayLine(_ line: String) {
    let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty, !isGenericStatusLine(t) else { return }
    // Nunca piná texto já cortado com reticências.
    if t.hasSuffix("…") || t.hasSuffix("...") { return }
    CompanionAppGroup.defaults.set(t, forKey: displayLineKey)
    UserDefaults.standard.set(t, forKey: displayLineKey)
  }

  static func displayLine() -> String? {
    let raw: String? = {
      if let s = CompanionAppGroup.defaults.string(forKey: displayLineKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
         !s.isEmpty {
        return s
      }
      if let s = UserDefaults.standard.string(forKey: displayLineKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
         !s.isEmpty {
        return s
      }
      if let idle = load()?.idleLine?.trimmingCharacters(in: .whitespacesAndNewlines),
         !idle.isEmpty {
        return idle
      }
      return nil
    }()
    guard let raw, !isGenericStatusLine(raw) else { return nil }
    if let full = expandTruncated(raw) {
      saveDisplayLine(full)
      return full
    }
    if raw.hasSuffix("…") || raw.hasSuffix("...") { return nil }
    return raw
  }

  /// Se o pin antigo veio truncado ("…"), tenta achar a frase completa no feed/idle.
  static func expandTruncated(_ text: String) -> String? {
    var stem = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if stem.hasSuffix("…") { stem = String(stem.dropLast()) }
    if stem.hasSuffix("...") { stem = String(stem.dropLast(3)) }
    stem = stem.trimmingCharacters(in: .whitespacesAndNewlines)
    guard stem.count >= 12 else { return nil }

    if let hit = ThoughtFeedStore.load().reversed().first(where: {
      $0.text.hasPrefix(stem) && $0.text.count > stem.count
    }) {
      return hit.text
    }
    if let idle = load()?.idleLine?.trimmingCharacters(in: .whitespacesAndNewlines),
       idle.hasPrefix(stem),
       idle.count > stem.count,
       !idle.hasSuffix("…") {
      return idle
    }
    return nil
  }

  static func clearMusic() {
    guard let cur = load() else { return }
    save(
      WidgetSpeechPayload(
        name: cur.name,
        idleLine: cur.idleLine,
        trackTitle: nil,
        trackArtist: nil,
        comment: nil,
        updatedAt: Date()
      )
    )
  }
}

enum WidgetReloader {
  static func reload() {
    WidgetCenter.shared.reloadAllTimelines()
  }
}
