import Foundation

/// Telemetria passiva no foreground — sem BGTaskScheduler (evita SIGKILL em times
/// sem Background Modes capability completa / Personal Team).
enum BackgroundTelemetry {
  /// Chamada ao abrir / voltar ao app — passos + mídia + context-ingest.
  @MainActor
  static func runForegroundIngest() async {
    ContextTelemetryService.shared.start()
    await HealthKitStepsService.shared.refreshAndIngest()
    NowPlayingService.shared.refresh()
    await ContextTelemetryService.shared.ingestNow(appForeground: true)
  }

  /// No-op: background refresh desligado de propósito (estabilidade do launch).
  static func register() {}
  static func schedule() {}
}
