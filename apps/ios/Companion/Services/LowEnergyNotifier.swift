import Foundation
import UserNotifications

/// Avisa quando a energia cai abaixo do limiar (anti-spam 12h).
enum LowEnergyNotifier {
  static let thresholdPercent = 25
  private static let enabledKey = "companion.lowEnergyNotifEnabled"
  private static let lastSentKey = "companion.lowEnergyNotifLastSent"
  private static let cooldown: TimeInterval = 12 * 60 * 60
  private static let notifId = "companion.low-energy"

  static var isEnabled: Bool {
    get {
      if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
      return UserDefaults.standard.bool(forKey: enabledKey)
    }
    set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
  }

  @discardableResult
  static func requestPermission() async -> Bool {
    do {
      return try await UNUserNotificationCenter.current()
        .requestAuthorization(options: [.alert, .sound, .badge])
    } catch {
      return false
    }
  }

  static func check(energyPercent: Int, companionName: String) {
    guard isEnabled else { return }
    guard energyPercent < thresholdPercent else { return }

    let now = Date().timeIntervalSince1970
    let last = UserDefaults.standard.double(forKey: lastSentKey)
    guard now - last >= cooldown else { return }

    Task {
      let settings = await UNUserNotificationCenter.current().notificationSettings()
      guard settings.authorizationStatus == .authorized
        || settings.authorizationStatus == .provisional else { return }

      let content = UNMutableNotificationContent()
      content.title = companionName
      content.body = "Estou com pouca energia… vem me dar um feed?"
      content.sound = .default

      let request = UNNotificationRequest(
        identifier: notifId,
        content: content,
        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
      )
      do {
        try await UNUserNotificationCenter.current().add(request)
        UserDefaults.standard.set(now, forKey: lastSentKey)
      } catch {
        print("[notif] \(error.localizedDescription)")
      }
    }
  }
}
