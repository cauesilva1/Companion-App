import ActivityKit
import Foundation
import WidgetKit

@MainActor
enum LiveActivityController {
  /// Inicia a corrida na Island. Animação no widget via `startedAt` (wall clock).
  /// Já agenda dismiss — se o app morrer, a Island some sozinha e não fica travada.
  @discardableResult
  static func start(snapshot: CompanionSnapshot, line: String? = nil) async throws -> String {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      throw LiveActivityError.disabled
    }

    await endAll()

    let startedAt = Date()
    let attributes = CompanionAttributes(
      companionId: snapshot.id,
      skin: snapshot.skin,
      startedAt: startedAt
    )
    let track = NowPlayingService.shared.line ?? ""
    let state = CompanionAttributes.ContentState.from(
      snapshot: snapshot,
      line: line,
      track: track
    )
    let dismissAt = startedAt.addingTimeInterval(IslandTiming.total + 0.75)
    let content = ActivityContent(state: state, staleDate: dismissAt, relevanceScore: 100)

    let activity = try Activity.request(
      attributes: attributes,
      content: content,
      pushType: nil
    )

    let alert = AlertConfiguration(
      title: LocalizedStringResource(stringLiteral: snapshot.name),
      body: LocalizedStringResource(
        stringLiteral: line ?? track.nilIfEmpty ?? "Correndo na Island…"
      ),
      sound: .default
    )
    await activity.update(
      ActivityContent(state: state, staleDate: dismissAt, relevanceScore: 100),
      alertConfiguration: alert
    )

    // Agenda o fim: permanece visível até dismissAt, depois some (mesmo com app morto).
    await activity.end(content, dismissalPolicy: .after(dismissAt))

    Task { @MainActor in
      await playIslandSounds(startedAt: startedAt)
    }

    return activity.id
  }

  static func update(snapshot: CompanionSnapshot, line: String? = nil) async {
    let track = NowPlayingService.shared.line ?? ""
    let state = CompanionAttributes.ContentState.from(snapshot: snapshot, line: line, track: track)
    let content = ActivityContent(
      state: state,
      staleDate: Date().addingTimeInterval(60),
      relevanceScore: 80
    )
    for act in Activity<CompanionAttributes>.activities {
      await act.update(content)
    }
  }

  /// Encerra tudo na hora (voltar ao app / fechar app).
  static func endAll() async {
    for activity in Activity<CompanionAttributes>.activities {
      let content = ActivityContent(state: activity.content.state, staleDate: nil)
      await activity.end(content, dismissalPolicy: .immediate)
    }
  }

  /// Encerra Islands já expiradas (legado / órfãs).
  static func endExpired() async {
    for activity in Activity<CompanionAttributes>.activities {
      if IslandTiming.isExpired(startedAt: activity.attributes.startedAt) {
        let content = ActivityContent(state: activity.content.state, staleDate: nil)
        await activity.end(content, dismissalPolicy: .immediate)
      }
    }
  }

  /// Sons só enquanto o processo do app está vivo (background). Kill = para na hora.
  private static func playIslandSounds(startedAt: Date) async {
    let steps = IslandTiming.updateSteps
    let stepDuration = IslandTiming.total / Double(steps)
    var lastPhase: IslandTiming.Phase = .run
    var lastStepSound = Date.distantPast

    for i in 0...steps {
      if IslandTiming.isExpired(startedAt: startedAt, grace: 0) { return }

      let progress = Double(i) / Double(steps)
      let phase = IslandTiming.phase(at: progress)

      if phase == .run {
        let now = Date()
        if now.timeIntervalSince(lastStepSound) >= 0.22 {
          SoundService.playStep()
          lastStepSound = now
        }
      } else if phase == .hurt, lastPhase == .run {
        SoundService.playHurt()
      }
      lastPhase = phase

      if i < steps {
        try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
      }
    }
  }
}

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
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
