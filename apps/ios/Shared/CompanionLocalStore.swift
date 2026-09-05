import Foundation

struct StoredCompanion: Codable, Equatable, Sendable {
  var id: String
  var name: String
  var personality: String
  var skin: String
  var artStyle: String
  var backdrop: String
  var archetype: String
  var mood: CompanionMood
  var energy: Double
  var affection: Double
  var lastDecayAt: Date
  var lastInteractionAt: Date
  var pendingAlert: String?
  var memoryNotes: [String]
  var userDisplayName: String?

  func toSnapshot(moodText: String? = nil) -> CompanionSnapshot {
    CompanionSnapshot(
      id: id,
      name: name,
      mood: mood.rawValue,
      moodText: moodText ?? MoodEngine.moodText(name: name, mood: mood),
      energy: energy,
      affection: affection,
      skin: skin,
      archetype: archetype,
      updatedAt: Date()
    )
  }
}

struct StoredInteraction: Codable, Sendable {
  var id: String
  var companionId: String
  var type: InteractionType
  var userMessage: String?
  var reactionText: String
  var moodAfter: CompanionMood
  var energyAfter: Double
  var affectionAfter: Double
  var createdAt: Date
}

struct CompanionFileStore: Codable, Sendable {
  var companions: [StoredCompanion]
  var interactions: [StoredInteraction]
}

enum CompanionLocalStore {
  private static let key = "companion.local.store.v1"

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

  static func load() -> CompanionFileStore {
    if let data = CompanionAppGroup.defaults.data(forKey: key),
       let store = try? decoder.decode(CompanionFileStore.self, from: data) {
      return store
    }
    if let data = UserDefaults.standard.data(forKey: key),
       let store = try? decoder.decode(CompanionFileStore.self, from: data) {
      return store
    }
    return CompanionFileStore(companions: [], interactions: [])
  }

  static func save(_ store: CompanionFileStore) {
    guard let data = try? encoder.encode(store) else { return }
    CompanionAppGroup.defaults.set(data, forKey: key)
    UserDefaults.standard.set(data, forKey: key)
  }

  static func nextId(prefix: String = "cmp") -> String {
    let rand = String(UUID().uuidString.prefix(5)).lowercased()
    return "\(prefix)-\(Int(Date().timeIntervalSince1970 * 1000))-\(rand)"
  }

  static func makeDefaultCompanion() -> StoredCompanion {
    let now = Date()
    let skins = ["dino-mort", "dino-doux", "dino-vita", "dino-olaf", "dino-kuro"]
    let arch = ["zoeiro", "curioso", "carinhoso", "preguicoso", "misterioso"].randomElement()!
    let skin = skins.randomElement()!
    let names: [String: String] = [
      "dino-mort": "Mort",
      "dino-doux": "Doux",
      "dino-vita": "Vita",
      "dino-olaf": "Olaf",
      "dino-kuro": "Kuro",
    ]
    return StoredCompanion(
      id: nextId(),
      name: names[skin] ?? "Companion",
      personality: arch,
      skin: skin,
      artStyle: "pixel",
      backdrop: "sky",
      archetype: arch,
      mood: .HAPPY,
      energy: 80,
      affection: 55,
      lastDecayAt: now,
      lastInteractionAt: now,
      pendingAlert: nil,
      memoryNotes: [],
      userDisplayName: nil
    )
  }
}
