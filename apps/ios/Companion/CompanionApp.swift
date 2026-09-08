import SwiftUI
import UIKit
import ActivityKit

@main
struct CompanionApp: App {
  @UIApplicationDelegateAdaptor(CompanionAppDelegate.self) private var appDelegate

  init() {
    // Spotify/Supabase no Keychain sobrevivem ao “Apagar App” — limpa na 1ª abertura.
    FreshInstall.resetKeychainIfReinstalled()
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}

/// Encerra Live Activities órfãs — com Island congelada, limpa tudo ao ficar ativo.
final class CompanionAppDelegate: NSObject, UIApplicationDelegate {
  func applicationDidBecomeActive(_ application: UIApplication) {
    Task { @MainActor in
      if IslandTiming.animationFrozen {
        await LiveActivityController.endAll()
      }
      await HealthKitStepsService.shared.refreshAndIngest()
    }
  }
}
