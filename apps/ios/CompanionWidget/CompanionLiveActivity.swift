import ActivityKit
import WidgetKit
import SwiftUI

struct CompanionLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CompanionAttributes.self) { context in
      Group {
        if IslandTiming.animationFrozen {
          frozenBanner(context: context)
        } else {
          TimelineView(.periodic(from: context.attributes.startedAt, by: 1.0 / 30.0)) { timeline in
            let progress = IslandTiming.progress(since: context.attributes.startedAt, now: timeline.date)
            let phase = IslandTiming.phase(at: progress)
            VStack(spacing: 6) {
              IslandRunThenHurtView(
                skin: context.attributes.skin,
                progress: progress,
                phase: phase,
                size: 48,
                segment: .full
              )
              .frame(maxWidth: .infinity)
              if !context.state.line.isEmpty {
                Text(context.state.line)
                  .font(.caption.weight(.semibold))
                  .lineLimit(2)
                  .foregroundStyle(.primary)
              }
              HStack {
                Text("⚡\(context.state.energy)%")
                  .font(.caption2.monospacedDigit())
                if !context.state.track.isEmpty {
                  Text("♪ \(context.state.track)")
                    .font(.caption2)
                    .lineLimit(1)
                }
              }
              .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
          }
        }
      }
      .activityBackgroundTint(Color.cyan.opacity(0.15))
      .activitySystemActionForegroundColor(.primary)
    } dynamicIsland: { context in
      let skin = context.attributes.skin
      let startedAt = context.attributes.startedAt

      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) { EmptyView() }
        DynamicIslandExpandedRegion(.trailing) {
          Text("⚡\(context.state.energy)")
            .font(.caption2.monospacedDigit().weight(.bold))
        }
        DynamicIslandExpandedRegion(.center) {
          if !context.state.track.isEmpty {
            Text(context.state.track)
              .font(.caption2)
              .lineLimit(1)
          } else {
            Color.clear.frame(height: 4)
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          if IslandTiming.animationFrozen {
            HStack(spacing: 8) {
              DinoStaticFrame(skin: skin, size: 36)
              if !context.state.line.isEmpty {
                Text(context.state.line)
                  .font(.caption2)
                  .lineLimit(1)
              }
              Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
          } else {
            TimelineView(.periodic(from: startedAt, by: 1.0 / 30.0)) { timeline in
              let progress = IslandTiming.progress(since: startedAt, now: timeline.date)
              let phase = IslandTiming.phase(at: progress)
              VStack(spacing: 4) {
                IslandRunThenHurtView(
                  skin: skin,
                  progress: progress,
                  phase: phase,
                  size: 44,
                  segment: .full
                )
                .frame(maxWidth: .infinity)
                if !context.state.line.isEmpty {
                  Text(context.state.line)
                    .font(.caption2)
                    .lineLimit(1)
                }
              }
              .padding(.horizontal, 6)
              .padding(.bottom, 4)
            }
          }
        }
      } compactLeading: {
        if IslandTiming.animationFrozen {
          DinoStaticFrame(skin: skin, size: 18)
            .frame(width: 56, height: 22)
        } else {
          TimelineView(.periodic(from: startedAt, by: 1.0 / 30.0)) { timeline in
            let progress = IslandTiming.progress(since: startedAt, now: timeline.date)
            let phase = IslandTiming.phase(at: progress)
            if phase == .done || phase == .fade {
              Color.clear.frame(width: 56, height: 22)
            } else {
              IslandRunThenHurtView(
                skin: skin,
                progress: progress,
                phase: phase,
                size: 18,
                segment: .firstHalf
              )
              .frame(width: 56, height: 22)
            }
          }
        }
      } compactTrailing: {
        if IslandTiming.animationFrozen {
          Text("⚡\(context.state.energy)")
            .font(.caption2.monospacedDigit().weight(.bold))
            .frame(width: 56, height: 22)
        } else {
          TimelineView(.periodic(from: startedAt, by: 1.0 / 30.0)) { timeline in
            let progress = IslandTiming.progress(since: startedAt, now: timeline.date)
            let phase = IslandTiming.phase(at: progress)
            if phase == .done || phase == .fade {
              Color.clear.frame(width: 56, height: 22)
            } else {
              IslandRunThenHurtView(
                skin: skin,
                progress: progress,
                phase: phase,
                size: 18,
                segment: .secondHalf
              )
              .frame(width: 56, height: 22)
            }
          }
        }
      } minimal: {
        if IslandTiming.animationFrozen {
          DinoStaticFrame(skin: skin, size: 16)
        } else {
          TimelineView(.periodic(from: startedAt, by: 1.0 / 30.0)) { timeline in
            let phase = IslandTiming.phase(since: startedAt, now: timeline.date)
            if phase == .run || phase == .hurt {
              DinoStaticFrame(skin: skin, size: 16)
            } else {
              EmptyView()
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func frozenBanner(context: ActivityViewContext<CompanionAttributes>) -> some View {
    HStack(spacing: 10) {
      DinoStaticFrame(skin: context.attributes.skin, size: 40)
      VStack(alignment: .leading, spacing: 2) {
        if !context.state.line.isEmpty {
          Text(context.state.line)
            .font(.caption.weight(.semibold))
            .lineLimit(2)
        }
        Text("⚡\(context.state.energy)%")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 14)
  }
}
