import SwiftUI

struct ProfileView: View {
  @ObservedObject var model: CompanionViewModel
  @State private var stats: SupabaseClient.ProfileStatsDTO?
  @State private var loading = true
  @State private var errorText: String?
  @State private var equippingKey: String?
  @State private var toast: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        heroCard
        statsCard
        badgesSection
      }
      .padding(16)
    }
    .background(CompanionTheme.screenBackground)
    .navigationTitle("Perfil")
    .navigationBarTitleDisplayMode(.inline)
    .overlay(alignment: .bottom) {
      if let toast {
        Text(toast)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background(Capsule().fill(CompanionTheme.play))
          .padding(.bottom, 24)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .task { await reload() }
  }

  private var heroCard: some View {
    CompanionCard {
      HStack(spacing: 14) {
        DinoStaticFrame(skin: model.snapshot.skin, size: 72)
        VStack(alignment: .leading, spacing: 6) {
          Text(model.snapshot.name)
            .font(.title2.bold())
            .foregroundStyle(CompanionTheme.title)
          if let title = displayTitle {
            Text(title)
              .font(.caption.weight(.bold))
              .foregroundStyle(CompanionTheme.play)
              .padding(.horizontal, 8)
              .padding(.vertical, 3)
              .background(Capsule().fill(CompanionTheme.play.opacity(0.12)))
          }
          Text(CompanionLifeMode.parse(model.snapshot.lifeMode).labelPT)
            .font(.caption)
            .foregroundStyle(CompanionTheme.subtitle)
          Text(LocalVoice.archetypeLabel(model.snapshot.archetype))
            .font(.caption2)
            .foregroundStyle(CompanionTheme.subtitle)
        }
        Spacer(minLength: 0)
      }
    }
  }

  private var displayTitle: String? {
    let t = (stats?.activeTitle ?? model.snapshot.activeTitle)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return (t?.isEmpty == false) ? t : nil
  }

  private var statsCard: some View {
    CompanionCard {
      VStack(alignment: .leading, spacing: 12) {
        Text("Convivência")
          .font(.headline)
          .foregroundStyle(CompanionTheme.title)
        if loading && stats == nil {
          ProgressView()
            .tint(CompanionTheme.play)
        } else if let errorText, stats == nil {
          Text(errorText)
            .font(.caption)
            .foregroundStyle(.red)
          Button("Tentar de novo") { Task { await reload() } }
            .font(.caption.weight(.semibold))
        } else {
          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statChip(icon: "sofa.fill", label: "Sofá", value: hoursLabel(stats?.indoorHours))
            statChip(icon: "figure.walk", label: "Rua", value: hoursLabel(stats?.workHours))
            statChip(icon: "moon.zzz.fill", label: "Sono", value: hoursLabel(stats?.sleepHours))
            statChip(icon: "music.note", label: "Músicas", value: "\(stats?.musicCount ?? 0)")
            statChip(icon: "gamecontroller.fill", label: "Games", value: "\(stats?.gamingCount ?? 0)")
            statChip(icon: "calendar", label: "Dias juntos", value: daysLabel(stats?.daysAlive))
          }
        }
      }
    }
  }

  private var badgesSection: some View {
    CompanionCard {
      VStack(alignment: .leading, spacing: 12) {
        Text("Badges e títulos")
          .font(.headline)
          .foregroundStyle(CompanionTheme.title)
        Text("Toque numa badge desbloqueada para equipar o título.")
          .font(.caption)
          .foregroundStyle(CompanionTheme.subtitle)

        let badges = stats?.badges ?? []
        if badges.isEmpty && !loading {
          Text("Nenhuma badge ainda.")
            .font(.caption)
            .foregroundStyle(CompanionTheme.subtitle)
        }
        ForEach(badges) { badge in
          badgeRow(badge)
        }
      }
    }
  }

  private func badgeRow(_ badge: SupabaseClient.BadgeDTO) -> some View {
    let unlocked = badge.unlocked == true
    let equipped = badge.equipped == true
    let progress = badge.progress ?? 0
    let target = max(badge.target ?? 1, 0.0001)
    let ratio = min(1, max(0, progress / target))

    return Button {
      guard unlocked else { return }
      Task { await equip(badge) }
    } label: {
      HStack(alignment: .center, spacing: 12) {
        Image(systemName: badge.symbol ?? "medal.fill")
          .font(.title3)
          .foregroundStyle(unlocked ? CompanionTheme.play : Color.gray.opacity(0.45))
          .frame(width: 36, height: 36)
          .background(
            Circle().fill(unlocked ? CompanionTheme.play.opacity(0.12) : Color.gray.opacity(0.08))
          )

        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text(badge.label ?? badge.key)
              .font(.subheadline.weight(.bold))
              .foregroundStyle(unlocked ? CompanionTheme.title : Color.gray)
            if equipped {
              Text("Equipado")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(CompanionTheme.play))
            }
            Spacer(minLength: 0)
          }
          Text(badge.description ?? "")
            .font(.caption2)
            .foregroundStyle(unlocked ? CompanionTheme.subtitle : Color.gray.opacity(0.7))
            .lineLimit(2)
          if !unlocked {
            ProgressView(value: ratio)
              .tint(Color.gray.opacity(0.5))
            Text(badge.hint ?? "")
              .font(.caption2)
              .foregroundStyle(Color.gray)
          } else if !equipped {
            Text("Toque para equipar")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(CompanionTheme.play)
          }
        }

        if equippingKey == badge.key {
          ProgressView()
            .scaleEffect(0.8)
        }
      }
      .padding(.vertical, 6)
      .opacity(unlocked ? 1 : 0.85)
    }
    .buttonStyle(.plain)
    .disabled(!unlocked || equippingKey != nil)
  }

  private func statChip(icon: String, label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Label(label, systemImage: icon)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(CompanionTheme.subtitle)
        .labelStyle(.titleAndIcon)
      Text(value)
        .font(.subheadline.weight(.bold))
        .foregroundStyle(CompanionTheme.title)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.black.opacity(0.03))
    )
  }

  private func hoursLabel(_ hours: Double?) -> String {
    let h = hours ?? 0
    if h < 10 { return String(format: "%.1fh", h) }
    return "\(Int(h.rounded()))h"
  }

  private func daysLabel(_ days: Double?) -> String {
    let d = days ?? 0
    if d < 2 { return String(format: "%.1f", d) }
    return "\(Int(d.rounded()))"
  }

  @MainActor
  private func reload() async {
    loading = true
    errorText = nil
    defer { loading = false }
    do {
      let bundle = try await SupabaseClient.shared.fetchProfileStats()
      stats = bundle
      if let title = bundle.activeTitle {
        model.applyEquippedTitle(
          activeTitle: title,
          titleKey: bundle.titleKey,
          equippedTitleKey: bundle.equippedTitleKey
        )
      }
    } catch {
      errorText = error.localizedDescription
    }
  }

  @MainActor
  private func equip(_ badge: SupabaseClient.BadgeDTO) async {
    equippingKey = badge.key
    defer { equippingKey = nil }
    do {
      let result = try await SupabaseClient.shared.equipTitle(badge.key)
      model.applyEquippedTitle(
        activeTitle: result.activeTitle ?? badge.label,
        titleKey: result.titleKey ?? badge.key,
        equippedTitleKey: result.equippedTitleKey ?? badge.key
      )
      await reload()
      withAnimation {
        toast = "Título equipado: \(result.activeTitle ?? badge.label ?? badge.key)"
      }
      try? await Task.sleep(nanoseconds: 1_800_000_000)
      withAnimation { toast = nil }
    } catch {
      errorText = error.localizedDescription
    }
  }
}
