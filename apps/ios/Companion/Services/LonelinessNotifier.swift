import Foundation
import UserNotifications

/// Avisa quando o humor fica LONELY / SAD (saudade).
enum LonelinessNotifier {
  private static let enabledKey = "companion.missYouNotifEnabled"
  private static let lastSentKey = "companion.missYouNotifLastSent"
  private static let cooldown: TimeInterval = 18 * 60 * 60
  private static let notifId = "companion.miss-you"

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

  static func check(mood: String, companionName: String) {
    guard isEnabled else { return }
    let upper = mood.uppercased()
    guard upper == "LONELY" || upper == "SAD" else { return }

    let now = Date().timeIntervalSince1970
    let last = UserDefaults.standard.double(forKey: lastSentKey)
    guard now - last >= cooldown else { return }

    Task {
      let settings = await UNUserNotificationCenter.current().notificationSettings()
      guard settings.authorizationStatus == .authorized
        || settings.authorizationStatus == .provisional else { return }

      let content = UNMutableNotificationContent()
      content.title = companionName
      content.body = upper == "LONELY"
        ? "Senti sua falta… vem me visitar?"
        : "Tô meio pra baixo… um poke ajudaria."
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
        print("[notif-miss] \(error.localizedDescription)")
      }
    }
  }
}
