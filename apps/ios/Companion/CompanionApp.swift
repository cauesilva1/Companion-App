import SwiftUI
import UIKit
import ActivityKit

@main
struct CompanionApp: App {
  @UIApplicationDelegateAdaptor(CompanionAppDelegate.self) private var appDelegate

  init() {
    // Spotify/Supabase no Keychain sobrevivem ao “Apagar App” — limpa na 1ª abertura.
    FreshInstall.resetKeychainIfReinstalled()
    Growth.isEnabled = false
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}

/// Launch leve — telemetria pesada fica no `scenePhase` / bootstrap (após a UI subir).
final class CompanionAppDelegate: NSObject, UIApplicationDelegate {
  func applicationDidBecomeActive(_ application: UIApplication) {
    Task { @MainActor in
      if IslandTiming.animationFrozen {
        await LiveActivityController.endAll()
      }
    }
  }
}
