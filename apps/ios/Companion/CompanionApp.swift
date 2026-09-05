import SwiftUI
import UIKit
import ActivityKit

@main
struct CompanionApp: App {
  @UIApplicationDelegateAdaptor(CompanionAppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}

/// Encerra Live Activities se o sistema notificar término (fechar app).
final class CompanionAppDelegate: NSObject, UIApplicationDelegate {
  func applicationWillTerminate(_ application: UIApplication) {
    let sem = DispatchSemaphore(value: 0)
    Task { @MainActor in
      await LiveActivityController.endAll()
      sem.signal()
    }
    // Espera breve para o end disparar antes do processo morrer.
    _ = sem.wait(timeout: .now() + 0.8)
  }
}
