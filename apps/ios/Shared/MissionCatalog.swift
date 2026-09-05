import Foundation

/// Missões diárias locais (offline) — espelham a API.
struct LocalMission: Codable, Identifiable, Equatable {
  var id: String
  var kind: String
  var title: String
  var description: String
  var target: Int
  var progress: Int
  var rewardEnergy: Int
  var rewardAffection: Int
  var claimed: Bool

  var complete: Bool { progress >= target }
}

enum MissionCatalog {
  private static let storeKey = "companion.missions.v1"

  private static let rotation: [[(kind: String, title: String, description: String, target: Int, e: Int, a: Int)]] = [
    [
      ("POKE_COUNT", "Cutucadas", "Cutuca o dino 3 vezes", 3, 6, 4),
      ("FEED_COUNT", "Lanche", "Alimente 2 vezes", 2, 10, 3),
      ("PLAY_COUNT", "Brincadeira", "Brinque 1 vez", 1, 8, 6),
    ],
    [
      ("CHAT_COUNT", "Conversa", "Mande 1 mensagem", 1, 5, 8),
      ("TEASE_COUNT", "Piadinha", "Mande 1 piada", 1, 7, 7),
      ("OPEN_APP", "Visita", "Abra o app 2 vezes hoje", 2, 4, 5),
    ],
    [
      ("POKE_COUNT", "Carinho", "Cutuca 5 vezes", 5, 8, 5),
      ("FEED_COUNT", "Banquete", "Alimente 3 vezes", 3, 12, 4),
      ("TEASE_COUNT", "Zoeira", "2 piadas no dia", 2, 9, 9),
    ],
  ]

  static func dayKey(_ date: Date = Date()) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withFullDate]
    return f.string(from: date)
  }

  static func ensureToday() -> [LocalMission] {
    let key = dayKey()
    if let existing = load(), existing.dayKey == key {
      return existing.missions
    }
    let n = key.split(separator: "-").compactMap { Int($0) }.reduce(0, +)
    let defs = rotation[n % rotation.count]
    let missions = defs.map { d in
      LocalMission(
        id: "local-\(key)-\(d.kind)",
        kind: d.kind,
        title: d.title,
        description: d.description,
        target: d.target,
        progress: 0,
        rewardEnergy: d.e,
        rewardAffection: d.a,
        claimed: false
      )
    }
    save(dayKey: key, missions: missions)
    return missions
  }

  static func bump(kind: String, amount: Int = 1) -> [LocalMission] {
    var missions = ensureToday()
    guard let idx = missions.firstIndex(where: { $0.kind == kind }) else { return missions }
    guard !missions[idx].claimed else { return missions }
    missions[idx].progress = min(missions[idx].target, missions[idx].progress + amount)
    save(dayKey: dayKey(), missions: missions)
    return missions
  }

  static func kindFromInteraction(_ type: String) -> String? {
    switch type.uppercased() {
    case "POKE": return "POKE_COUNT"
    case "FEED": return "FEED_COUNT"
    case "PLAY": return "PLAY_COUNT"
    case "CHAT": return "CHAT_COUNT"
    case "TEASE": return "TEASE_COUNT"
    default: return nil
    }
  }

  @discardableResult
  static func claim(_ id: String) -> (missions: [LocalMission], rewardEnergy: Int, rewardAffection: Int)? {
    var missions = ensureToday()
    guard let idx = missions.firstIndex(where: { $0.id == id }) else { return nil }
    let m = missions[idx]
    guard !m.claimed, m.complete else { return nil }
    missions[idx].claimed = true
    save(dayKey: dayKey(), missions: missions)
    return (missions, m.rewardEnergy, m.rewardAffection)
  }

  private struct Box: Codable {
    var dayKey: String
    var missions: [LocalMission]
  }

  private static func load() -> Box? {
    guard let data = UserDefaults.standard.data(forKey: storeKey) else { return nil }
    return try? JSONDecoder().decode(Box.self, from: data)
  }

  private static func save(dayKey: String, missions: [LocalMission]) {
    let box = Box(dayKey: dayKey, missions: missions)
    if let data = try? JSONEncoder().encode(box) {
      UserDefaults.standard.set(data, forKey: storeKey)
    }
  }
}
