import Foundation
import CoreGraphics

enum GrowthStage: String, Codable, Sendable {
  case baby, teen, adult
}

enum Growth {
  private static let enabledKey = "companion.growthEnabled"

  /// Visual growth + evolve. Default OFF (só forma base). Toggle em Config.
  static var isEnabled: Bool {
    get {
      if UserDefaults.standard.object(forKey: enabledKey) == nil { return false }
      return UserDefaults.standard.bool(forKey: enabledKey)
    }
    set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
  }

  /// Days required in the current stage before evolve is allowed.
  static let dwellDays: [GrowthStage: Double] = [
    .baby: 7,
    .teen: 14,
    .adult: .infinity,
  ]

  static let affectionMin: [GrowthStage: Double] = [
    .baby: 55,
    .teen: 70,
    .adult: 100,
  ]

  static func normalize(_ raw: String?) -> GrowthStage {
    switch (raw ?? "baby").lowercased() {
    case "teen": return .teen
    case "adult": return .adult
    default: return .baby
    }
  }

  /// Stage for sprites / scale / evolve. Forced to baby while growth is off.
  static func effective(_ raw: String?) -> GrowthStage {
    isEnabled ? normalize(raw) : .baby
  }

  /// Escala visual (mesmo desktop `growthScale`).
  static func scale(for stage: GrowthStage) -> CGFloat {
    guard isEnabled else { return 1 }
    switch stage {
    case .baby: return 0.88
    case .teen: return 1.0
    case .adult: return 1.14
    }
  }

  static func scale(forRaw raw: String?) -> CGFloat {
    scale(for: effective(raw))
  }

  static func next(after stage: GrowthStage) -> GrowthStage? {
    switch stage {
    case .baby: return .teen
    case .teen: return .adult
    case .adult: return nil
    }
  }

  static func evolveClip(from: GrowthStage, to: GrowthStage) -> DinoClip? {
    guard isEnabled else { return nil }
    if from == .baby, to == .teen { return .evolveBabyTeen }
    if from == .teen, to == .adult { return .evolveTeenAdult }
    return nil
  }

  static func wordLimit(for stage: GrowthStage) -> Int {
    let s = isEnabled ? stage : .baby
    switch s {
    case .baby: return 10
    case .teen: return 16
    case .adult: return 22
    }
  }

  static func voiceHint(for stage: GrowthStage) -> String {
    let s = isEnabled ? stage : .baby
    let max = wordLimit(for: s)
    switch s {
    case .baby:
      return "Fase: bebe. Fale simples, grudento e inocente; giria minima. No maximo \(max) palavras."
    case .teen:
      return "Fase: adolescente. Mais atitude e energia; espelhe o arquétipo. No maximo \(max) palavras."
    case .adult:
      return "Fase: adulto. Mais maduro e calmo, ainda fiel ao arquétipo. No maximo \(max) palavras."
    }
  }

  /// Progressão lenta: dias **na fase atual** (growthStageAt) + affection.
  static func shouldEvolve(
    stage: GrowthStage,
    stageStartedAt: Date,
    affection: Double,
    now: Date = Date()
  ) -> GrowthStage? {
    guard isEnabled else { return nil }
    guard next(after: stage) != nil else { return nil }
    let days = now.timeIntervalSince(stageStartedAt) / (24 * 60 * 60)
    let needDays = dwellDays[stage] ?? .infinity
    let needAffection = affectionMin[stage] ?? 100
    if days >= needDays, affection >= needAffection {
      return next(after: stage)
    }
    return nil
  }

  /// Returns stage + whether stageStartedAt should reset to now.
  static func resolve(
    stageRaw: String?,
    stageStartedAt: Date?,
    createdAt: Date?,
    affection: Double,
    now: Date = Date()
  ) -> (stage: GrowthStage, stageStartedAt: Date) {
    let stage = normalize(stageRaw)
    let started = stageStartedAt ?? createdAt ?? now
    if let next = shouldEvolve(stage: stage, stageStartedAt: started, affection: affection, now: now) {
      return (next, now)
    }
    return (stage, started)
  }
}
