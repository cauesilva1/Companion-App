import Foundation
import Network
import CoreLocation
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
  @Published private(set) var locationAuthorized = false

  private let monitor = NWPathMonitor()
  private var started = false

  func start() {
    guard !started else { return }
    started = true
    #if canImport(UIKit)
    UIDevice.current.isBatteryMonitoringEnabled = true
    #endif
    locationAuthorized = LocationHelper.shared.isWhenInUseAuthorized
    monitor.pathUpdateHandler = { [weak self] path in
      Task { @MainActor in
        self?.onWifi = path.usesInterfaceType(.wifi)
      }
    }
    monitor.start(queue: DispatchQueue(label: "companion.context.path"))
  }

  /// Pede When In Use antes de ler SSID (Settings / ingest).
  @discardableResult
  func ensureLocationForWifiSsid() async -> Bool {
    start()
    let status = await LocationHelper.shared.ensureWhenInUseAuthorized()
    let ok: Bool
    switch status {
    case .authorizedWhenInUse, .authorizedAlways:
      ok = true
    default:
      ok = false
    }
    locationAuthorized = ok
    return ok
  }

  func ingestNow(appForeground: Bool? = nil) async {
    start()
    _ = await ensureLocationForWifiSsid()

    let foreground: Bool = {
      if let appForeground { return appForeground }
      #if canImport(UIKit)
      return UIApplication.shared.applicationState == .active
      #else
      return true
      #endif
    }()

    let ssid = await currentSsid()
    lastSsid = ssid
    let home = LifeModeStore.homeWifiSsid

    // true = em casa, false = fora com certeza, nil = desconhecido (não forçar work)
    let onHome: Bool? = {
      if let home, let ssid {
        return home.caseInsensitiveCompare(ssid) == .orderedSame
      }
      if !onWifi { return false }
      // Wi‑Fi ligado mas SSID ilegível → unknown (evita falso work)
      return nil
    }()

    let stepsToday = HealthKitStepsService.shared.todaySteps
    let stepsRecent = await recentStepsApprox()
    let charging = isCharging()
    let hour = Calendar.current.component(.hour, from: Date())
    let mediaLine = NowPlayingService.shared.line
    let mediaActive = mediaLine != nil && !(mediaLine?.isEmpty ?? true)

    _ = HouseZoneStore.resolveActiveZone(ssid: ssid)

    guard SupabaseConfig.isConfigured, KeychainStore.get(.supabaseAccess) != nil else {
      let mode = localHeuristic(
        onHome: onHome,
        hour: hour,
        alreadySleep: lastLifeMode == .sleep,
        appForeground: foreground
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
        xboxGamertag: LifeModeStore.xboxGamertag,
        appForeground: foreground
      )
      let mode = CompanionLifeMode.parse(result.lifeMode)
      lastLifeMode = mode
      LifeModeStore.saveMode(mode)
      HouseZoneStore.syncWithLifeMode(mode)
      if let morning = result.morningThought, !morning.isEmpty {
        LifeModeStore.pendingMorningThought = morning
      }
      // Snapshot espelho local de mídia/Xbox para LLM/feed
      if var snap = CompanionSnapshotStore.load() {
        if let media = result.mediaHint { snap.mediaHint = media }
        else if mediaActive { snap.mediaHint = mediaLine }
        else if !mediaActive { snap.mediaHint = nil }
        if let gaming = result.gamingStatus { snap.gamingStatus = gaming }
        if let lm = result.lifeMode { snap.lifeMode = lm }
        if let title = result.activeTitle { snap.activeTitle = title }
        if let tk = result.titleKey { snap.titleKey = tk }
        if let ek = result.equippedTitleKey { snap.equippedTitleKey = ek }
        CompanionSnapshotStore.save(snap)
      }
      if result.thoughts != nil {
        // ThoughtFeedStore já atualizado em ingestContext
      }
    } catch {
      print("[context] ingest: \(error.localizedDescription)")
    }
  }

  /// Captura SSID atual após garantir Location When In Use.
  func captureCurrentSsidAsHome() async -> String? {
    let authorized = await ensureLocationForWifiSsid()
    guard authorized else { return nil }
    let ssid = await currentSsid()
    guard let ssid, !ssid.isEmpty else { return nil }
    LifeModeStore.homeWifiSsid = ssid
    await ingestNow(appForeground: true)
    return ssid
  }

  private func localHeuristic(
    onHome: Bool?,
    hour: Int,
    alreadySleep: Bool,
    appForeground: Bool
  ) -> CompanionLifeMode {
    let inBed = hour >= CompanionLifeMode.bedtimeHour || hour < CompanionLifeMode.wakeHour
    let canWake = appForeground
      && hour >= CompanionLifeMode.wakeHour
      && hour < CompanionLifeMode.bedtimeHour

    let dayMode: CompanionLifeMode = {
      if onHome == false && hour >= 7 && hour < 19 { return .work }
      return .indoor
    }()

    if alreadySleep {
      return canWake ? dayMode : .sleep
    }
    if inBed { return .sleep }
    return dayMode
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
    return min(today, Int(Double(today) / Double(hour) * 2.0))
  }
}
