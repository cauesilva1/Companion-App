import Foundation

enum CompanionMood: String, Codable, CaseIterable, Sendable {
  case EXCITED, HAPPY, CONTENT, BORED, SLEEPY, SAD, LONELY
}

enum InteractionType: String, Codable, Sendable {
  case POKE, FEED, PLAY, CHAT, TEASE, IGNORE_CHECK
}

enum MoodEngine {
  private static let affectionDecayPerHour = 2.0 / 24.0
  private static let energyDecayPerHour = 0.5

  static func clamp(_ value: Double, min: Double = 0, max: Double = 100) -> Double {
    Swift.max(min, Swift.min(max, value))
  }

  static func computeMood(affection: Double, energy: Double, daysSinceInteraction: Double = 0) -> CompanionMood {
    if daysSinceInteraction > 3 { return .LONELY }
    if energy < 18 { return .SLEEPY }
    if affection < 18 { return .SAD }
    if affection < 32 { return .BORED }
    if affection > 75 && energy > 40 { return .EXCITED }
    if affection > 42 { return .HAPPY }
    return .CONTENT
  }

  static func applyTimeDecay(
    energy: Double,
    affection: Double,
    lastInteractionAt: Date,
    now: Date = Date()
  ) -> (energy: Double, affection: Double, mood: CompanionMood) {
    let hours = now.timeIntervalSince(lastInteractionAt) / 3600
    let hoursIdle = max(0, hours - 1)
    let nextAffection = clamp(affection - hoursIdle * affectionDecayPerHour)
    let nextEnergy = clamp(energy - hoursIdle * energyDecayPerHour)
    let days = hours / 24
    return (nextEnergy, nextAffection, computeMood(affection: nextAffection, energy: nextEnergy, daysSinceInteraction: days))
  }

  static func applyInteraction(
    energy: Double,
    affection: Double,
    type: InteractionType
  ) -> (energy: Double, affection: Double, mood: CompanionMood) {
    let fx: (affection: Double, energy: Double)
    switch type {
    case .POKE: fx = (2, -1)
    case .FEED: fx = (0, 8)
    case .PLAY: fx = (6, -4)
    case .CHAT: fx = (4, -2)
    case .TEASE: fx = (5, -2)
    case .IGNORE_CHECK: fx = (-4, -2)
    }
    let nextAffection = clamp(affection + fx.affection)
    let nextEnergy = clamp(energy + fx.energy)
    return (nextEnergy, nextAffection, computeMood(affection: nextAffection, energy: nextEnergy))
  }

  static func moodText(name: String, mood: CompanionMood) -> String {
    let phrase: String
    switch mood {
    case .EXCITED: phrase = "empolgado"
    case .HAPPY: phrase = "feliz"
    case .CONTENT: phrase = "tranquilo"
    case .BORED: phrase = "entediado"
    case .SLEEPY: phrase = "com sono"
    case .SAD: phrase = "triste"
    case .LONELY: phrase = "sentindo sua falta"
    }
    return "\(name) está \(phrase)"
  }
}
