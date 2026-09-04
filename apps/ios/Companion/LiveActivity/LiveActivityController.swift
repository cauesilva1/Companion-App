import ActivityKit
import Foundation
import WidgetKit

enum LiveActivityController {
  @discardableResult
  static func start(snapshot: CompanionSnapshot, line: String? = nil) throws -> String {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      throw LiveActivityError.disabled
    }
    let attributes = CompanionAttributes(companionId: snapshot.id, skin: snapshot.skin)
    let state = CompanionAttributes.ContentState.from(snapshot: snapshot, line: line)
    let activity = try Activity.request(
      attributes: attributes,
      contentState: state,
      pushType: nil
    )
    return activity.id
  }

  static func update(snapshot: CompanionSnapshot, line: String? = nil) async {
    let state = CompanionAttributes.ContentState.from(snapshot: snapshot, line: line)
    for activity in Activity<CompanionAttributes>.activities {
      await activity.update(using: state)
    }
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
