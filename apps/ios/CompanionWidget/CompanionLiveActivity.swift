import ActivityKit
import WidgetKit
import SwiftUI

struct CompanionLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CompanionAttributes.self) { context in
      // Banner / lock — só o dino correndo → dano → some
      IslandRunThenHurtView(
        skin: context.attributes.skin,
        startedAt: context.attributes.startedAt,
        size: 48
      )
      .frame(maxWidth: .infinity)
      .padding(.vertical, 10)
      .padding(.horizontal, 14)
      .activityBackgroundTint(Color.cyan.opacity(0.2))
      .activitySystemActionForegroundColor(.primary)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          EmptyView()
        }
        DynamicIslandExpandedRegion(.trailing) {
          EmptyView()
        }
        DynamicIslandExpandedRegion(.center) {
          EmptyView()
        }
        DynamicIslandExpandedRegion(.bottom) {
          IslandRunThenHurtView(
            skin: context.attributes.skin,
            startedAt: context.attributes.startedAt,
            size: 40
          )
          .frame(maxWidth: .infinity)
          .padding(.horizontal, 4)
        }
      } compactLeading: {
        IslandRunThenHurtView(
          skin: context.attributes.skin,
          startedAt: context.attributes.startedAt,
          size: 18
        )
        .frame(width: 52, height: 22)
      } compactTrailing: {
        // Sem bateria / energia — espaço vazio
        EmptyView()
      } minimal: {
        DinoAvatar(skin: context.attributes.skin, size: 16)
          .opacity(islandStillVisible(startedAt: context.attributes.startedAt) ? 1 : 0)
      }
    }
  }

  private func islandStillVisible(startedAt: Date) -> Bool {
    Date().timeIntervalSince(startedAt) < IslandTiming.total
  }
}
