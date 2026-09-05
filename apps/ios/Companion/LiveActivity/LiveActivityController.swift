import ActivityKit
import Foundation
import WidgetKit

enum LiveActivityController {
  @discardableResult
  static func start(snapshot: CompanionSnapshot, line: String? = nil) throws -> String {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      throw LiveActivityError.disabled
    }

    if let current = Activity<CompanionAttributes>.activities.first {
      let elapsed = Date().timeIntervalSince(current.attributes.startedAt)
      if elapsed < IslandTiming.total {
        return current.id
      }
      Task { await endActivity(current) }
    }

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
    let stale = startedAt.addingTimeInterval(IslandTiming.total + 8.0)
    let content = ActivityContent(state: state, staleDate: stale, relevanceScore: 100)

    let activity = try Activity.request(
      attributes: attributes,
      content: content,
      pushType: nil
    )

    let activityId = activity.id
    let alertTitle = snapshot.name
    let alertBody = line ?? track.nilIfEmpty ?? "Correndo na Island…"
    Task {
      let alert = AlertConfiguration(
        title: LocalizedStringResource(stringLiteral: alertTitle),
        body: LocalizedStringResource(stringLiteral: alertBody),
        sound: .default
      )
      await activity.update(
        ActivityContent(state: state, staleDate: stale, relevanceScore: 100),
        alertConfiguration: alert
      )
      await animateIsland(
        activityId: activityId,
        skin: snapshot.skin,
        line: line ?? snapshot.moodText,
        energy: snapshot.energyPercent,
        track: track
      )
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

  static func endAll() async {
    for activity in Activity<CompanionAttributes>.activities {
      await endActivity(activity)
    }
  }

  private static func animateIsland(
    activityId: String,
    skin: String,
    line: String,
    energy: Int,
    track: String
  ) async {
    let steps = IslandTiming.updateSteps
    let stepDuration = IslandTiming.total / Double(steps)
    var lastPhase: IslandTiming.Phase = .run
    var lastStepSound = Date.distantPast

    for i in 0...steps {
      let progress = Double(i) / Double(steps)
      let phase = IslandTiming.phase(at: progress)
      let state = CompanionAttributes.ContentState(
        skin: skin,
        runProgress: progress,
        phase: phase.rawValue,
        line: line,
        energy: energy,
        track: track
      )
      let content = ActivityContent(
        state: state,
        staleDate: Date().addingTimeInterval(IslandTiming.total)
      )
      for act in Activity<CompanionAttributes>.activities where act.id == activityId {
        await act.update(content)
      }

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
    for act in Activity<CompanionAttributes>.activities where act.id == activityId {
      await endActivity(act)
    }
  }

  private static func endActivity(_ activity: Activity<CompanionAttributes>) async {
    let content = ActivityContent(state: activity.content.state, staleDate: nil)
    await activity.end(content, dismissalPolicy: .immediate)
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
