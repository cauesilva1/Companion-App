import ActivityKit
import Foundation

/// Live Activity / Dynamic Island — dino + frase viva.
struct CompanionAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable, Sendable {
    var skin: String
    /// 0…1 ao longo de IslandTiming.total
    var runProgress: Double
    var phase: String
    var line: String
    var energy: Int
    var track: String

    var islandPhase: IslandTiming.Phase {
      IslandTiming.Phase(rawValue: phase) ?? .run
    }
  }

  var companionId: String
  var skin: String
  var startedAt: Date
}

extension CompanionAttributes.ContentState {
  static func initial(
    skin: String,
    line: String = "",
    energy: Int = 80,
    track: String = ""
  ) -> Self {
    Self(
      skin: skin,
      runProgress: 0,
      phase: IslandTiming.Phase.run.rawValue,
      line: line,
      energy: energy,
      track: track
    )
  }

  /// Status passivo contínuo (Dynamic Island / Live Activity).
  static func status(
    skin: String,
    line: String,
    energy: Int,
    affection: Int,
    presence: String,
    track: String = ""
  ) -> Self {
    Self(
      skin: skin,
      runProgress: Double(energy) / 100.0,
      phase: presence,
      line: line.isEmpty ? "energia \(energy)% · carinho \(affection)%" : line,
      energy: energy,
      track: track
    )
  }

  static func from(snapshot: CompanionSnapshot, line: String? = nil, track: String? = nil) -> Self {
    status(
      skin: snapshot.skin,
      line: line ?? snapshot.moodText,
      energy: snapshot.energyPercent,
      affection: snapshot.affectionPercent,
      presence: snapshot.presenceStatus ?? "present",
      track: track ?? ""
    )
  }

  static let demo = initial(skin: "dino-mort", line: "Oi!", energy: 72)
}
