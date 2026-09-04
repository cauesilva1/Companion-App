import ActivityKit
import Foundation

/// Live Activity / Dynamic Island — só o dino (sem energia/bateria).
struct CompanionAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable, Sendable {
    /// Mantido mínimo; a cena é dirigida por `startedAt` nos attributes.
    var skin: String
  }

  var companionId: String
  var skin: String
  var startedAt: Date
}

extension CompanionAttributes.ContentState {
  static func from(snapshot: CompanionSnapshot, line: String? = nil) -> Self {
    Self(skin: snapshot.skin)
  }

  static let demo = Self(skin: "dino-mort")
}
