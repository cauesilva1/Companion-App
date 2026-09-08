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
  }

  static func saveIdle(line: String, name: String) {
    var current = load()
    // Não apaga música recente
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
  }

  /// Remove faixa/comentário; preserva idleLine se existir.
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
