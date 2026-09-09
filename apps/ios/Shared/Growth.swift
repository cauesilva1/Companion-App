import Foundation
import CoreGraphics

/// Forma visual única (sem evolução). Mantido só para sprites/DB `growthStage`.
enum GrowthStage: String, Codable, Sendable {
  case baby, teen, adult
}

enum Growth {
  private static let enabledKey = "companion.growthEnabled"

  /// Sempre off — não há growth no produto.
  static var isEnabled: Bool {
    get { false }
    set { UserDefaults.standard.set(false, forKey: enabledKey) }
  }

  static func normalize(_ raw: String?) -> GrowthStage { .baby }

  static func effective(_ raw: String?) -> GrowthStage { .baby }

  static func scale(for stage: GrowthStage) -> CGFloat { 1 }

  static func scale(forRaw raw: String?) -> CGFloat { 1 }

  static func next(after stage: GrowthStage) -> GrowthStage? { nil }

  static func evolveClip(from: GrowthStage, to: GrowthStage) -> DinoClip? { nil }

  static func chatWordLimit(energy: Double = 70) -> Int {
    let e = Int(energy.rounded())
    if e < 18 { return 28 }
    if e < 40 { return 45 }
    return 70
  }

  static func chatVoiceHint(energy: Double = 70) -> String {
    let max = chatWordLimit(energy: energy)
    return "Fale como companion vivo e natural, com personalidade. No maximo \(max) palavras."
  }

  /// Sem evolução: sempre forma base.
  static func resolve(
    stageRaw: String?,
    stageStartedAt: Date?,
    createdAt: Date?,
    affection: Double,
    now: Date = Date()
  ) -> (stage: GrowthStage, stageStartedAt: Date) {
    ( .baby, stageStartedAt ?? createdAt ?? now )
  }
}
