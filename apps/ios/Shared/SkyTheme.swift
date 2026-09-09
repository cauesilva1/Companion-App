import SwiftUI

enum SkyPeriod: String {
  case dawn, day, evening, night, storm, cloudy, snowy

  static func current(date: Date = Date()) -> SkyPeriod {
    let hour = Calendar.current.component(.hour, from: date)
    switch hour {
    case 5..<8: return .dawn
    case 8..<17: return .day
    case 17..<20: return .evening
    default: return .night
    }
  }

  /// Mapeia condição canônica da cloud + hora local → plate de céu.
  static func from(weather: String?, hour: Int = Calendar.current.component(.hour, from: Date())) -> SkyPeriod {
    switch (weather ?? "").lowercased() {
    case "rainy": return .storm
    case "snowy": return .snowy
    case "cloudy": return .cloudy
    case "night": return .night
    case "sunny":
      switch hour {
      case 5..<8: return .dawn
      case 8..<17: return .day
      case 17..<20: return .evening
      default: return .night
      }
    default:
      return .current(date: Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date())
    }
  }

  /// Resolução compartilhada. Preferência: weather → plate salvo → hora.
  static func resolved(snapshotWeather: String? = nil) -> SkyPeriod {
    if let w = snapshotWeather?.trimmingCharacters(in: .whitespacesAndNewlines), !w.isEmpty {
      return from(weather: w)
    }
    if let w = CompanionSnapshotStore.loadWeatherCondition() {
      return from(weather: w)
    }
    if let sky = CompanionSnapshotStore.loadSkyPeriod() {
      return sky
    }
    return .current()
  }

  var imageName: String { rawValue }

  var gradient: LinearGradient {
    switch self {
    case .dawn:
      return LinearGradient(
        colors: [Color(red: 1.0, green: 0.72, blue: 0.55), Color(red: 0.88, green: 0.93, blue: 1.0)],
        startPoint: .top, endPoint: .bottom
      )
    case .day:
      return LinearGradient(
        colors: [Color(red: 0.55, green: 0.82, blue: 0.98), Color(red: 0.93, green: 0.96, blue: 1.0)],
        startPoint: .top, endPoint: .bottom
      )
    case .evening:
      return LinearGradient(
        colors: [Color(red: 0.95, green: 0.55, blue: 0.40), Color(red: 0.92, green: 0.88, blue: 0.98)],
        startPoint: .top, endPoint: .bottom
      )
    case .night:
      return LinearGradient(
        colors: [Color(red: 0.12, green: 0.18, blue: 0.35), Color(red: 0.22, green: 0.28, blue: 0.45)],
        startPoint: .top, endPoint: .bottom
      )
    case .storm:
      return LinearGradient(
        colors: [Color(red: 0.38, green: 0.42, blue: 0.50), Color(red: 0.62, green: 0.68, blue: 0.76)],
        startPoint: .top, endPoint: .bottom
      )
    case .cloudy:
      return LinearGradient(
        colors: [Color(red: 0.62, green: 0.70, blue: 0.80), Color(red: 0.88, green: 0.91, blue: 0.95)],
        startPoint: .top, endPoint: .bottom
      )
    case .snowy:
      return LinearGradient(
        colors: [Color(red: 0.72, green: 0.84, blue: 0.95), Color(red: 0.92, green: 0.96, blue: 1.0)],
        startPoint: .top, endPoint: .bottom
      )
    }
  }

  /// Opacidade da arte — chuva/neve um pouco mais visíveis.
  var preferredArtOpacity: Double {
    switch self {
    case .storm, .snowy: return 0.42
    case .cloudy, .night: return 0.34
    default: return 0.30
    }
  }

  /// Texto claro no topo (noite/tempestade).
  var prefersLightChrome: Bool {
    self == .night || self == .storm
  }
}

/// Céu full-bleed: plate em tela cheia + véu suave (sem faixa dura no meio).
struct SkyBackground: View {
  var period: SkyPeriod = .current()
  /// Se nil, usa `period.preferredArtOpacity`.
  var artOpacity: Double? = nil

  private var resolvedArtOpacity: Double {
    artOpacity ?? period.preferredArtOpacity
  }

  var body: some View {
    GeometryReader { geo in
      ZStack {
        period.gradient

        Image(period.imageName)
          .resizable()
          .scaledToFill()
          .frame(width: geo.size.width, height: geo.size.height)
          .clipped()
          .opacity(resolvedArtOpacity)
          .allowsHitTesting(false)

        // Véu contínuo do topo (transparente) ao rodapé (mais sólido) — sem corte em 55%.
        LinearGradient(
          colors: [
            Color.white.opacity(0.05),
            Color.white.opacity(0.18),
            Color(red: 0.95, green: 0.97, blue: 1.0).opacity(0.55),
            Color(red: 0.94, green: 0.96, blue: 0.99).opacity(0.82),
          ],
          startPoint: .top,
          endPoint: .bottom
        )
        .allowsHitTesting(false)
      }
    }
    .ignoresSafeArea()
    .animation(.easeInOut(duration: 1.0), value: period)
  }
}
