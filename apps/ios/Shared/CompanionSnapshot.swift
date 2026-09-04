import Foundation

/// Chaves compartilhadas entre app, widget e Live Activity (App Group).
enum CompanionAppGroup {
  static let id = "group.com.companion.tamagotchi"
  static let snapshotKey = "companion.snapshot.v1"
  static let companionIdKey = "companion.id"
  static let apiBaseKey = "companion.apiBase"

  static var defaults: UserDefaults {
    UserDefaults(suiteName: id) ?? .standard
  }
}

struct CompanionSnapshot: Codable, Equatable, Sendable {
  var id: String
  var name: String
  var mood: String
  var moodText: String
  var energy: Double
  var affection: Double
  var skin: String
  var archetype: String
  var updatedAt: Date

  static let demo = CompanionSnapshot(
    id: "demo",
    name: "zezinho",
    mood: "HAPPY",
    moodText: "zezinho está feliz",
    energy: 72,
    affection: 80,
    skin: "dino-mort",
    archetype: "zoeiro",
    updatedAt: Date()
  )

  var energyPercent: Int { Int(energy.rounded()) }
  var affectionPercent: Int { Int(affection.rounded()) }

  var moodEmoji: String {
    switch mood.uppercased() {
    case "EXCITED": return "✨"
    case "HAPPY": return "😊"
    case "CONTENT": return "😌"
    case "BORED": return "😐"
    case "SLEEPY": return "😴"
    case "SAD": return "😢"
    case "LONELY": return "🥺"
    default: return "🦕"
    }
  }
}

enum CompanionSnapshotStore {
  static func save(_ snapshot: CompanionSnapshot) {
    guard let data = try? JSONEncoder().encode(snapshot) else { return }
    CompanionAppGroup.defaults.set(data, forKey: CompanionAppGroup.snapshotKey)
    CompanionAppGroup.defaults.set(snapshot.id, forKey: CompanionAppGroup.companionIdKey)
  }

  static func load() -> CompanionSnapshot? {
    guard let data = CompanionAppGroup.defaults.data(forKey: CompanionAppGroup.snapshotKey) else {
      return nil
    }
    return try? JSONDecoder().decode(CompanionSnapshot.self, from: data)
  }
}
