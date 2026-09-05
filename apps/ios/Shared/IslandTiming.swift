import Foundation

/// Tempos da cena na Dynamic Island (A corre → B dano → C some).
enum IslandTiming {
  static let runDuration: TimeInterval = 1.4
  static let hurtDuration: TimeInterval = 0.45
  static let fadeDuration: TimeInterval = 0.28
  static var total: TimeInterval { runDuration + hurtDuration + fadeDuration }

  static let updateSteps = 42

  enum Phase: String, Codable, Sendable {
    case run, hurt, fade, done
  }

  static func phase(at progress: Double) -> Phase {
    let t = max(0, min(1, progress)) * total
    if t < runDuration { return .run }
    if t < runDuration + hurtDuration { return .hurt }
    if t < total { return .fade }
    return .done
  }

  /// 0…1 só na fase de corrida (posição horizontal).
  static func runX(at progress: Double) -> Double {
    let t = max(0, min(1, progress)) * total
    if t >= runDuration { return 1 }
    let u = t / runDuration
    return u * u * (3 - 2 * u)
  }
}
