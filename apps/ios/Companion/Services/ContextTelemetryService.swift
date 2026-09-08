import Foundation
import Network
#if canImport(UIKit)
import UIKit
#endif
#if canImport(NetworkExtension)
import NetworkExtension
#endif

/// Telemetria leve do aparelho → Edge `context-ingest` (lifeMode + mídia).
@MainActor
final class ContextTelemetryService: ObservableObject {
  static let shared = ContextTelemetryService()

  @Published private(set) var lastLifeMode: CompanionLifeMode = LifeModeStore.loadMode()
  @Published private(set) var lastSsid: String?
  @Published private(set) var onWifi = false

  private let monitor = NWPathMonitor()
  private var started = false

  func start() {
    guard !started else { return }
    started = true
    #if canImport(UIKit)
    UIDevice.current.isBatteryMonitoringEnabled = true
    #endif
    monitor.pathUpdateHandler = { [weak self] path in
      Task { @MainActor in
        self?.onWifi = path.usesInterfaceType(.wifi)
      }
    }
    monitor.start(queue: DispatchQueue(label: "companion.context.path"))
  }

  func ingestNow() async {
    start()
    let ssid = await currentSsid()
    lastSsid = ssid
    let home = LifeModeStore.homeWifiSsid
    let onHome: Bool? = {
      if let home, let ssid {
        return home.caseInsensitiveCompare(ssid) == .orderedSame
      }
      if !onWifi { return false }
      return nil
    }()

    let stepsToday = HealthKitStepsService.shared.todaySteps
    let stepsRecent = await recentStepsApprox()
    let charging = isCharging()
    let hour = Calendar.current.component(.hour, from: Date())
    let mediaLine = NowPlayingService.shared.line
    let mediaActive = mediaLine != nil && !(mediaLine?.isEmpty ?? true)

    HouseZoneStore.resolveActiveZone(ssid: ssid)

    guard SupabaseConfig.isConfigured, KeychainStore.get(.supabaseAccess) != nil else {
      // Offline heuristic for UI
      let mode = localHeuristic(
        onHome: onHome ?? false,
        hour: hour,
        stepsRecent: stepsRecent,
        charging: charging
      )
      lastLifeMode = mode
      LifeModeStore.saveMode(mode)
      return
    }

    do {
      let result = try await SupabaseClient.shared.ingestContext(
        onHomeWifi: onHome,
        ssid: ssid,
        stepsToday: stepsToday,
        stepsRecent: stepsRecent,
        isCharging: charging,
        localHour: hour,
        mediaActive: mediaActive,
        mediaHint: mediaLine,
        homeWifiSsid: home,
        xboxGamertag: LifeModeStore.xboxGamertag
      )
      let mode = CompanionLifeMode.parse(result.lifeMode)
      lastLifeMode = mode
      LifeModeStore.saveMode(mode)
      if let morning = result.morningThought, !morning.isEmpty {
        LifeModeStore.pendingMorningThought = morning
      }
    } catch {
      print("[context] ingest: \(error.localizedDescription)")
    }
  }

  /// Captura SSID atual (requer entitlement Wi‑Fi Info + Location quando o SO exigir).
  func captureCurrentSsidAsHome() async -> String? {
    let ssid = await currentSsid()
    guard let ssid, !ssid.isEmpty else { return nil }
    LifeModeStore.homeWifiSsid = ssid
    await ingestNow()
    return ssid
  }

  private func localHeuristic(onHome: Bool, hour: Int, stepsRecent: Int, charging: Bool) -> CompanionLifeMode {
    if hour >= 0 && hour < 6 && stepsRecent < 80 && (charging || stepsRecent < 20) {
      return .sleep
    }
    if !onHome && hour >= 7 && hour < 19 {
      return .work
    }
    return .indoor
  }

  private func isCharging() -> Bool {
    #if canImport(UIKit)
    switch UIDevice.current.batteryState {
    case .charging, .full: return true
    default: return false
    }
    #else
    return false
    #endif
  }

  private func currentSsid() async -> String? {
    #if canImport(NetworkExtension)
    await withCheckedContinuation { cont in
      NEHotspotNetwork.fetchCurrent { network in
        cont.resume(returning: network?.ssid)
      }
    }
    #else
    return nil
    #endif
  }

  /// Aproximação: usa total do dia como proxy se não houver janela 2h (HealthKit detalhado depois).
  private func recentStepsApprox() async -> Int {
    let today = HealthKitStepsService.shared.todaySteps
    let hour = max(1, Calendar.current.component(.hour, from: Date()))
    // Estimativa grosseira da “atividade recente” a partir do ritmo do dia.
    return min(today, Int(Double(today) / Double(hour) * 2.0))
  }
}
