import ActivityKit
import Foundation
import WidgetKit

@MainActor
enum LiveActivityController {
  /// Island congelada — não inicia / atualiza; encerra órfãs.
  private static var isFrozen: Bool { IslandTiming.animationFrozen }

  /// Presença passiva contínua na Island / Live Activity (status cloud).
  @discardableResult
  static func startPersistent(snapshot: CompanionSnapshot, line: String? = nil) async throws -> String {
    if isFrozen {
      await endAll()
      return "frozen"
    }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      throw LiveActivityError.disabled
    }

    let track = NowPlayingService.shared.line ?? ""
    let statusLine = line
      ?? presenceLine(snapshot)
      ?? snapshot.moodText
    let state = CompanionAttributes.ContentState.status(
      skin: snapshot.skin,
      line: statusLine,
      energy: snapshot.energyPercent,
      affection: snapshot.affectionPercent,
      presence: snapshot.presenceStatus ?? "present",
      track: track
    )

    if let existing = Activity<CompanionAttributes>.activities.first {
      let content = ActivityContent(
        state: state,
        staleDate: Date().addingTimeInterval(60 * 30),
        relevanceScore: 90
      )
      await existing.update(content)
      return existing.id
    }

    let attributes = CompanionAttributes(
      companionId: snapshot.id,
      skin: snapshot.skin,
      startedAt: Date()
    )
    let content = ActivityContent(
      state: state,
      staleDate: Date().addingTimeInterval(60 * 30),
      relevanceScore: 90
    )
    let activity = try Activity.request(
      attributes: attributes,
      content: content,
      pushType: nil
    )
    return activity.id
  }

  /// Vignette curta legada (corrida) — preferir `startPersistent` no modo passivo.
  @discardableResult
  static func start(snapshot: CompanionSnapshot, line: String? = nil) async throws -> String {
    try await startPersistent(snapshot: snapshot, line: line)
  }

  static func update(snapshot: CompanionSnapshot, line: String? = nil) async {
    if isFrozen {
      await endAll()
      return
    }
    let track = NowPlayingService.shared.line ?? ""
    let state = CompanionAttributes.ContentState.status(
      skin: snapshot.skin,
      line: line ?? presenceLine(snapshot) ?? snapshot.moodText,
      energy: snapshot.energyPercent,
      affection: snapshot.affectionPercent,
      presence: snapshot.presenceStatus ?? "present",
      track: track
    )
    let content = ActivityContent(
      state: state,
      staleDate: Date().addingTimeInterval(60 * 30),
      relevanceScore: 80
    )
    for act in Activity<CompanionAttributes>.activities {
      await act.update(content)
    }
  }

  static func endAll() async {
    for activity in Activity<CompanionAttributes>.activities {
      let content = ActivityContent(state: activity.content.state, staleDate: nil)
      await activity.end(content, dismissalPolicy: .immediate)
    }
  }

  static func endExpired() async {
    if isFrozen {
      await endAll()
    }
  }

  private static func presenceLine(_ snap: CompanionSnapshot) -> String? {
    let mode = CompanionLifeMode.parse(snap.lifeMode)
    switch mode {
    case .sleep:
      return "\(snap.name) hibernando · decay pausado"
    case .work:
      return "\(snap.name) no campo · \(snap.energyPercent)% energia"
    case .indoor:
      return "\(snap.name) em casa · \(snap.energyPercent)% energia"
    }
  }
}

enum LiveActivityError: LocalizedError {
  case disabled
  var errorDescription: String? { "Live Activities desativadas" }
}
