import Foundation

/// Tempos da cena na Dynamic Island (app fechado continua via TimelineView).
enum IslandTiming {
  static let runDuration: TimeInterval = 2.2
  static let hurtDuration: TimeInterval = 0.55
  static let fadeDuration: TimeInterval = 0.28
  static var total: TimeInterval { runDuration + hurtDuration + fadeDuration }
}
