import Foundation
#if canImport(UIKit)
import UIKit
#endif
import UserNotifications

enum PrankKind: String, CaseIterable {
  case shake
  case bounce
  case notify
  case teaseSound = "tease-sound"
  case hideAndSeek = "hide-and-seek"
}

@MainActor
final class PrankController: ObservableObject {
  @Published var offset: CGSize = .zero
  @Published var scale: CGFloat = 1
  @Published var hidden = false
  @Published var line: String?

  private static let enabledKey = "companion.pranksEnabled"
  private var ambientTask: Task<Void, Never>?

  static var isEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: enabledKey) }
    set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
  }

  func setEnabled(_ on: Bool) {
    Self.isEnabled = on
    if on {
      startAmbient()
    } else {
      ambientTask?.cancel()
      ambientTask = nil
      resetVisual()
    }
  }

  func startAmbient() {
    ambientTask?.cancel()
    guard Self.isEnabled else { return }
    ambientTask = Task { [weak self] in
      while !Task.isCancelled {
        let minutes = Double.random(in: 5...15)
        try? await Task.sleep(nanoseconds: UInt64(minutes * 60 * 1_000_000_000))
        guard !Task.isCancelled, let self, Self.isEnabled else { continue }
        await self.run(PrankKind.allCases.randomElement() ?? .shake)
      }
    }
  }

  func stopAmbient() {
    ambientTask?.cancel()
    ambientTask = nil
  }

  func run(_ kind: PrankKind) async {
    switch kind {
    case .shake:
      #if canImport(UIKit)
      UINotificationFeedbackGenerator().notificationOccurred(.error)
      #endif
      for _ in 0..<8 {
        offset = CGSize(width: CGFloat.random(in: -12...12), height: CGFloat.random(in: -8...8))
        try? await Task.sleep(nanoseconds: 40_000_000)
      }
      offset = .zero
      line = "Ops… terremoto de dino!"

    case .bounce:
      #if canImport(UIKit)
      UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
      #endif
      scale = 1.28
      offset = CGSize(width: 0, height: -18)
      try? await Task.sleep(nanoseconds: 280_000_000)
      scale = 1
      offset = .zero
      line = "Pulo surpresa!"

    case .notify:
      await notifyPrank("Ei… tô te zoando daqui 👀")
      line = "Notificação zoeira enviada."

    case .teaseSound:
      SoundService.play("growl")
      SoundService.play("hit")
      #if canImport(UIKit)
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      #endif
      line = "Grrr… pegadinha sonora."

    case .hideAndSeek:
      hidden = true
      line = "Cadê eu? 👻"
      await notifyPrank("Cadê o dino?…")
      let secs = Double.random(in: 2...4)
      try? await Task.sleep(nanoseconds: UInt64(secs * 1_000_000_000))
      hidden = false
      line = "Achei! 👀"
      #if canImport(UIKit)
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      #endif
    }
  }

  func resetVisual() {
    offset = .zero
    scale = 1
    hidden = false
  }

  private func notifyPrank(_ body: String) async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    guard settings.authorizationStatus == .authorized
      || settings.authorizationStatus == .provisional else { return }
    let content = UNMutableNotificationContent()
    content.title = "Companion"
    content.body = body
    content.sound = .default
    let req = UNNotificationRequest(
      identifier: "companion.prank.\(UUID().uuidString)",
      content: content,
      trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.3, repeats: false)
    )
    try? await center.add(req)
  }
}
