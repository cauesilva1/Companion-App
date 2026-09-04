import ActivityKit
import Foundation
import WidgetKit

enum LiveActivityController {
  /// Inicia a Island: dino corre → leva dano na borda → some.
  /// Continua com o app fechado; encerra sozinha após a cena.
  @discardableResult
  static func start(snapshot: CompanionSnapshot, line: String? = nil) throws -> String {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      throw LiveActivityError.disabled
    }

    // Encerra atividades anteriores para não empilhar
    let existing = Activity<CompanionAttributes>.activities
    for old in existing {
      Task { await old.end(using: nil, dismissalPolicy: .immediate) }
    }

    let startedAt = Date()
    let attributes = CompanionAttributes(
      companionId: snapshot.id,
      skin: snapshot.skin,
      startedAt: startedAt
    )
    let state = CompanionAttributes.ContentState.from(snapshot: snapshot, line: line)
    let stale = startedAt.addingTimeInterval(IslandTiming.total + 0.8)
    let content = ActivityContent(state: state, staleDate: stale)

    let activity = try Activity.request(
      attributes: attributes,
      content: content,
      pushType: nil
    )

    // Se o app ainda estiver vivo, encerra limpo após a cena
    let activityId = activity.id
    Task {
      let ns = UInt64((IslandTiming.total + 0.35) * 1_000_000_000)
      try? await Task.sleep(nanoseconds: ns)
      for act in Activity<CompanionAttributes>.activities where act.id == activityId {
        await act.end(using: nil, dismissalPolicy: .immediate)
      }
    }

    return activity.id
  }

  static func update(snapshot: CompanionSnapshot, line: String? = nil) async {
    // Island é one-shot (correr → dano → sumir); não atualiza stats/bateria.
    _ = snapshot
    _ = line
  }

  static func endAll() async {
    for activity in Activity<CompanionAttributes>.activities {
      await activity.end(using: nil, dismissalPolicy: .immediate)
    }
  }
}

enum LiveActivityError: LocalizedError {
  case disabled
  var errorDescription: String? { "Live Activities desativadas neste iPhone" }
}

enum WidgetReloader {
  static func reload() {
    WidgetCenter.shared.reloadAllTimelines()
  }
}
