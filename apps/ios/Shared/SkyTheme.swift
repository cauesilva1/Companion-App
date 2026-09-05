import SwiftUI

enum SkyPeriod: String {
  case dawn, day, evening, night, storm

  static func current(date: Date = Date()) -> SkyPeriod {
    let hour = Calendar.current.component(.hour, from: date)
    switch hour {
    case 5..<8: return .dawn
    case 8..<17: return .day
    case 17..<20: return .evening
    default: return .night
    }
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
        colors: [Color(red: 0.40, green: 0.45, blue: 0.52), Color(red: 0.75, green: 0.80, blue: 0.88)],
        startPoint: .top, endPoint: .bottom
      )
    }
  }

  /// Texto claro no topo (noite/tempestade).
  var prefersLightChrome: Bool {
    self == .night || self == .storm
  }
}

/// Céu legível atrás da UI: gradiente + imagem suave e clipada (sem “faixas” do PNG por cima dos cards).
struct SkyBackground: View {
  var period: SkyPeriod = .current()
  /// Opacidade da arte — baixa no app para não apagar textos.
  var artOpacity: Double = 0.28

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .top) {
        period.gradient
        Image(period.imageName)
          .resizable()
          .scaledToFill()
          .frame(width: geo.size.width, height: geo.size.height * 0.55, alignment: .top)
          .clipped()
          .opacity(artOpacity)
          .allowsHitTesting(false)
        // Véu claro na metade inferior para cards/texto sempre contrastarem
        VStack(spacing: 0) {
          Spacer()
          LinearGradient(
            colors: [Color.white.opacity(0), Color.white.opacity(0.72), Color(red: 0.95, green: 0.97, blue: 1.0).opacity(0.92)],
            startPoint: .top,
            endPoint: .bottom
          )
          .frame(height: geo.size.height * 0.55)
        }
        .allowsHitTesting(false)
      }
    }
    .ignoresSafeArea()
  }
}
