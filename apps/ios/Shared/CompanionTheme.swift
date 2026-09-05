import SwiftUI

/// Visual do mockup companion-ios-ui-final (cards claros pastel).
enum CompanionTheme {
  static let bgTop = Color(red: 0.90, green: 0.95, blue: 1.0)
  static let bgBottom = Color(red: 0.98, green: 0.99, blue: 1.0)
  static let title = Color(red: 0.15, green: 0.25, blue: 0.45)
  static let subtitle = Color(red: 0.40, green: 0.50, blue: 0.65)
  static let card = Color.white
  static let poke = Color(red: 0.30, green: 0.82, blue: 0.55)
  static let feed = Color(red: 1.0, green: 0.45, blue: 0.62)
  static let play = Color(red: 0.35, green: 0.55, blue: 0.98)
  static let energy = Color(red: 0.25, green: 0.85, blue: 0.55)
  static let affection = Color(red: 1.0, green: 0.45, blue: 0.65)
  static let chipOnline = Color(red: 0.25, green: 0.78, blue: 0.45)

  static var screenBackground: some View {
    LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
      .ignoresSafeArea()
  }
}

struct CompanionCard<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    content()
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(Color.white)
          .shadow(color: Color.black.opacity(0.12), radius: 12, y: 5)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(Color.black.opacity(0.06), lineWidth: 1)
      )
  }
}

struct StatBar: View {
  let title: String
  let systemImage: String
  let value: Int
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: systemImage)
          .foregroundStyle(color)
        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(CompanionTheme.subtitle)
        Spacer()
        Text("\(value)%")
          .font(.caption.monospacedDigit().weight(.bold))
          .foregroundStyle(CompanionTheme.title)
      }
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.black.opacity(0.06))
          Capsule()
            .fill(color)
            .frame(width: max(8, geo.size.width * CGFloat(value) / 100))
        }
      }
      .frame(height: 10)
    }
  }
}
