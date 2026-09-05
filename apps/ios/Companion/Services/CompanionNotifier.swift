import Foundation
import UserNotifications

/// Agenda notificações locais proativas (saudade / energia) enquanto o app ainda está vivo.
enum CompanionNotifier {
  private static let missId = "companion.proactive.miss"
  private static let energyId = "companion.proactive.energy"

  static func scheduleProactive(snapshot: CompanionSnapshot) {
    Task {
      let center = UNUserNotificationCenter.current()
      let settings = await center.notificationSettings()
      if settings.authorizationStatus == .notDetermined {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
      }
      let after = await center.notificationSettings()
      guard after.authorizationStatus == .authorized || after.authorizationStatus == .provisional else {
        return
      }

      center.removePendingNotificationRequests(withIdentifiers: [missId, energyId])

      if LonelinessNotifier.isEnabled {
        let miss = UNMutableNotificationContent()
        miss.title = snapshot.name
        miss.body = "Senti sua falta… vem me visitar?"
        miss.sound = .default
        let missTrigger = UNTimeIntervalNotificationTrigger(timeInterval: 14 * 3600, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: missId, content: miss, trigger: missTrigger))
      }

      if LowEnergyNotifier.isEnabled {
        // Decay ~0.5/h após graça — estima horas até ~40%
        let energy = Double(snapshot.energyPercent)
        let hoursUntilLow = max(2, (energy - 40) / 0.5)
        let seconds = min(36 * 3600, max(2 * 3600, hoursUntilLow * 3600))
        let energyContent = UNMutableNotificationContent()
        energyContent.title = snapshot.name
        energyContent.body = "Energia caindo… um feed ajudaria."
        energyContent.sound = .default
        let energyTrigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        try? await center.add(
          UNNotificationRequest(identifier: energyId, content: energyContent, trigger: energyTrigger)
        )
      }
    }
  }
}
