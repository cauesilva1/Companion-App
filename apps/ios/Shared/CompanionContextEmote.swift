import SwiftUI

/// Emotes flutuantes (SF Symbols) sobre o dino, conforme contexto cloud.
struct CompanionContextEmoteOverlay: View {
  let snapshot: CompanionSnapshot
  @State private var bob = false

  private var symbol: String? {
    let mode = CompanionLifeMode.parse(snapshot.lifeMode)
    if mode == .sleep || mode.isPreWakeDrowsy {
      return "moon.zzz.fill"
    }
    if let media = snapshot.mediaHint?.trimmingCharacters(in: .whitespacesAndNewlines), !media.isEmpty {
      return "music.note"
    }
    if let gaming = snapshot.gamingStatus?.trimmingCharacters(in: .whitespacesAndNewlines),
       !gaming.isEmpty {
      return "gamecontroller.fill"
    }
    if snapshot.energyPercent < 25 {
      return "battery.25"
    }
    if snapshot.affectionPercent >= 85 {
      return "heart.fill"
    }
    return nil
  }

  private var tint: Color {
    let mode = CompanionLifeMode.parse(snapshot.lifeMode)
    if mode == .sleep { return .indigo }
    if snapshot.mediaHint?.isEmpty == false { return CompanionTheme.play }
    if snapshot.gamingStatus?.isEmpty == false { return .green }
    if snapshot.energyPercent < 25 { return CompanionTheme.energy }
    return CompanionTheme.affection
  }

  var body: some View {
    if let symbol {
      Image(systemName: symbol)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(tint)
        .padding(6)
        .background(Circle().fill(Color.white.opacity(0.92)))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .offset(x: 22, y: bob ? -26 : -22)
        .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: bob)
        .onAppear { bob = true }
        .accessibilityHidden(true)
    }
  }
}
