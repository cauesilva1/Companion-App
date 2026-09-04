import ActivityKit
import Foundation

/// Payload da Live Activity / Dynamic Island (app + extensão).
struct CompanionAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable, Sendable {
    var name: String
    var mood: String
    var moodText: String
    var energy: Int
    var affection: Int
    var line: String
    var skin: String
  }

  var companionId: String
}

extension CompanionAttributes.ContentState {
  static func from(snapshot: CompanionSnapshot, line: String? = nil) -> Self {
    Self(
      name: snapshot.name,
      mood: snapshot.mood,
      moodText: snapshot.moodText,
      energy: snapshot.energyPercent,
      affection: snapshot.affectionPercent,
      line: line ?? snapshot.moodText,
      skin: snapshot.skin
    )
  }

  static let demo = Self(
    name: "zezinho",
    mood: "HAPPY",
    moodText: "zezinho está feliz",
    energy: 72,
    affection: 80,
    line: "Tô na ilha. Me cutuca depois.",
    skin: "dino-mort"
  )
}
