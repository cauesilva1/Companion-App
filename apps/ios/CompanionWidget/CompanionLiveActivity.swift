import ActivityKit
import WidgetKit
import SwiftUI

struct CompanionLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CompanionAttributes.self) { context in
      // Lock screen / banner
      HStack(spacing: 12) {
        DinoAvatar(skin: context.state.skin, size: 48)
        VStack(alignment: .leading, spacing: 4) {
          Text(context.state.name).font(.headline)
          Text(context.state.line)
            .font(.caption)
            .lineLimit(2)
          HStack {
            Label("\(context.state.energy)%", systemImage: "bolt.fill")
            Label("\(context.state.affection)%", systemImage: "heart.fill")
          }
          .font(.caption2)
        }
        Spacer(minLength: 0)
      }
      .padding()
      .activityBackgroundTint(Color.cyan.opacity(0.25))
      .activitySystemActionForegroundColor(.primary)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          DinoAvatar(skin: context.state.skin, size: 40)
        }
        DynamicIslandExpandedRegion(.trailing) {
          VStack(alignment: .trailing) {
            Text("⚡\(context.state.energy)%").font(.caption.monospacedDigit())
            Text("❤️\(context.state.affection)%").font(.caption.monospacedDigit())
          }
        }
        DynamicIslandExpandedRegion(.center) {
          Text(context.state.name).font(.headline)
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text(context.state.line)
            .font(.caption)
            .lineLimit(2)
        }
      } compactLeading: {
        DinoAvatar(skin: context.state.skin, size: 22)
      } compactTrailing: {
        Text("\(context.state.energy)%")
          .font(.caption2.monospacedDigit())
      } minimal: {
        DinoAvatar(skin: context.state.skin, size: 18)
      }
    }
  }
}
