import Foundation

/// Entrada do feed passivo (pensamentos / falas autônomas do companion).
struct ThoughtFeedEntry: Codable, Identifiable, Equatable, Sendable {
  var id: String
  var text: String
  var createdAt: Date
  /// mood | presence | music | zone | cloud | chat
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

  @discardableResult
  static func append(_ entry: ThoughtFeedEntry) -> [ThoughtFeedEntry] {
    var items = load()
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
}
