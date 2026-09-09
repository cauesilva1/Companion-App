import Foundation

/// Entrada do feed passivo (pensamentos / falas autônomas do companion).
struct ThoughtFeedEntry: Codable, Identifiable, Equatable, Sendable {
  var id: String
  var text: String
  var createdAt: Date
  /// mood | presence | music | zone | cloud | chat | morning
  var kind: String
  var zoneName: String?

  static func make(
    text: String,
    kind: String,
    zoneName: String? = nil
  ) -> ThoughtFeedEntry {
    ThoughtFeedEntry(
      id: "th_\(UUID().uuidString.prefix(10))",
      text: text,
      createdAt: Date(),
      kind: kind,
      zoneName: zoneName
    )
  }
}

enum ThoughtFeedStore {
  private static let key = "companion.thoughtFeed.v1"
  private static let maxEntries = 80

  private static let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    return e
  }()

  private static let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
  }()

  static func load() -> [ThoughtFeedEntry] {
    let data = CompanionAppGroup.defaults.data(forKey: key)
      ?? UserDefaults.standard.data(forKey: key)
    guard let data,
          let items = try? decoder.decode([ThoughtFeedEntry].self, from: data)
    else { return [] }
    return items.sorted { $0.createdAt < $1.createdAt }
  }

  static func save(_ items: [ThoughtFeedEntry]) {
    let trimmed = Array(items.suffix(maxEntries))
    guard let data = try? encoder.encode(trimmed) else { return }
    CompanionAppGroup.defaults.set(data, forKey: key)
    UserDefaults.standard.set(data, forKey: key)
  }

  /// Substitui pelo feed da cloud **sem apagar** pensamentos locais recentes (widget/app).
  static func replaceAll(_ items: [ThoughtFeedEntry]) -> [ThoughtFeedEntry] {
    // Cloud vazia não deve limpar o que o widget/app acabou de mostrar.
    if items.isEmpty {
      return load()
    }
    let local = load()
    let cloudIds = Set(items.map(\.id))
    let cloudTexts = Set(items.map(\.text))
    let keepLocal = local.filter { entry in
      if cloudIds.contains(entry.id) { return false }
      if cloudTexts.contains(entry.text) { return false }
      // Mantém locais das últimas 24h (openFromWidget / autonomous ainda não na cloud)
      return Date().timeIntervalSince(entry.createdAt) < 24 * 3600
    }
    let merged = (items + keepLocal).sorted { $0.createdAt < $1.createdAt }
    let trimmed = Array(merged.suffix(maxEntries))
    save(trimmed)
    return trimmed
  }

  @discardableResult
  static func append(_ entry: ThoughtFeedEntry) -> [ThoughtFeedEntry] {
    var items = load()
    if items.contains(where: { $0.id == entry.id }) { return items }
    // Anti-spam: mesmo texto nos últimos 2 minutos
    if let last = items.last,
       last.text == entry.text,
       abs(last.createdAt.timeIntervalSince(entry.createdAt)) < 120 {
      return items
    }
    items.append(entry)
    save(items)
    return items
  }

  static func latestLine() -> String? {
    load().last?.text
  }

  static func clear() {
    CompanionAppGroup.defaults.removeObject(forKey: key)
    UserDefaults.standard.removeObject(forKey: key)
  }

  static func fromCloud(_ row: CloudThoughtDTO) -> ThoughtFeedEntry {
    let created: Date = {
      if let raw = row.createdAt {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw) ?? Date()
      }
      return Date()
    }()
    return ThoughtFeedEntry(
      id: row.id,
      text: row.text,
      createdAt: created,
      kind: row.kind ?? "mood",
      zoneName: row.zoneName
    )
  }
}

struct CloudThoughtDTO: Codable, Sendable {
  var id: String
  var text: String
  var kind: String?
  var zoneName: String?
  var createdAt: String?
  var lifeMode: String?
  var mediaHint: String?
  var gamingStatus: String?
}
