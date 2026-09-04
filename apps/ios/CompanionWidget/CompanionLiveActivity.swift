import ActivityKit
import WidgetKit
import SwiftUI

struct CompanionLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CompanionAttributes.self) { context in
      // Lock screen / banner
      HStack(spacing: 12) {
        Text(moodEmoji(context.state.mood))
          .font(.largeTitle)
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
          Text(moodEmoji(context.state.mood)).font(.title)
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
        Text(moodEmoji(context.state.mood))
      } compactTrailing: {
        Text("\(context.state.energy)%")
          .font(.caption2.monospacedDigit())
      } minimal: {
        Text(moodEmoji(context.state.mood))
      }
    }
  }

  private func moodEmoji(_ mood: String) -> String {
    switch mood.uppercased() {
    case "EXCITED": return "✨"
    case "HAPPY": return "😊"
    case "CONTENT": return "😌"
    case "BORED": return "😐"
    case "SLEEPY": return "😴"
    case "SAD": return "😢"
    case "LONELY": return "🥺"
    default: return "🦕"
    }
  }
}
