import Foundation
import SwiftUI

/// Chaves compartilhadas entre app, widget e Live Activity (App Group).
enum CompanionAppGroup {
  static let id = "group.com.companion.tamagotchi"
  static let snapshotKey = "companion.snapshot.v1"
  static let companionIdKey = "companion.id"
  static let apiBaseKey = "companion.apiBase"

  /// Personal Team às vezes não provisiona App Group — cai no standard.
  static var defaults: UserDefaults {
    if let suite = UserDefaults(suiteName: id) {
      // Smoke: se suite não persiste, ainda tentamos escrever nela + standard
      return suite
    }
    return .standard
  }

  static var usesAppGroup: Bool {
    UserDefaults(suiteName: id) != nil
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

  /// Nome do imageset em Media.xcassets
  var dinoImageName: String {
    Self.imageName(forSkin: skin)
  }

  static func imageName(forSkin skin: String) -> String {
    switch skin.lowercased() {
    case "dino-doux", "doux": return "DinoDoux"
    case "dino-vita", "vita": return "DinoVita"
    case "dino-olaf", "olaf": return "DinoOlaf"
    case "dino-kuro", "kuro": return "DinoKuro"
    case "dino-mort", "mort": return "DinoMort"
    default: return "DinoMort"
    }
  }
}

enum CompanionSnapshotStore {
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

  static func save(_ snapshot: CompanionSnapshot) {
    guard let data = try? encoder.encode(snapshot) else { return }
    // Escreve nos dois: App Group (widgets) + standard (fallback Personal Team)
    CompanionAppGroup.defaults.set(data, forKey: CompanionAppGroup.snapshotKey)
    CompanionAppGroup.defaults.set(snapshot.id, forKey: CompanionAppGroup.companionIdKey)
    UserDefaults.standard.set(data, forKey: CompanionAppGroup.snapshotKey)
    UserDefaults.standard.set(snapshot.id, forKey: CompanionAppGroup.companionIdKey)
  }

  static func load() -> CompanionSnapshot? {
    if let data = CompanionAppGroup.defaults.data(forKey: CompanionAppGroup.snapshotKey),
       let snap = try? decoder.decode(CompanionSnapshot.self, from: data) {
      return snap
    }
    if let data = UserDefaults.standard.data(forKey: CompanionAppGroup.snapshotKey),
       let snap = try? decoder.decode(CompanionSnapshot.self, from: data) {
      return snap
    }
    return nil
  }

  static func savedCompanionId() -> String? {
    if let id = CompanionAppGroup.defaults.string(forKey: CompanionAppGroup.companionIdKey), !id.isEmpty {
      return id
    }
    return UserDefaults.standard.string(forKey: CompanionAppGroup.companionIdKey)
  }

  static func saveCompanionId(_ id: String) {
    CompanionAppGroup.defaults.set(id, forKey: CompanionAppGroup.companionIdKey)
    UserDefaults.standard.set(id, forKey: CompanionAppGroup.companionIdKey)
  }

  static func saveApiBase(_ base: String) {
    CompanionAppGroup.defaults.set(base, forKey: CompanionAppGroup.apiBaseKey)
    UserDefaults.standard.set(base, forKey: CompanionAppGroup.apiBaseKey)
  }

  static func savedApiBase() -> String? {
    if let s = CompanionAppGroup.defaults.string(forKey: CompanionAppGroup.apiBaseKey), !s.isEmpty {
      return s
    }
    return UserDefaults.standard.string(forKey: CompanionAppGroup.apiBaseKey)
  }
}

/// Avatar do dino a partir do Asset Catalog compartilhado.
struct DinoAvatar: View {
  let skin: String
  var size: CGFloat = 96

  var body: some View {
    Image(CompanionSnapshot.imageName(forSkin: skin))
      .resizable()
      .interpolation(.none)
      .scaledToFit()
      .frame(width: size, height: size)
      .accessibilityLabel("Dino \(skin)")
  }
}
