import Foundation
import HealthKit

/// Lê passos (HealthKit) e envia para a cloud (`steps-ingest`).
@MainActor
final class HealthKitStepsService: ObservableObject {
  static let shared = HealthKitStepsService()

  private let store = HKHealthStore()
  @Published private(set) var authorized = false
  @Published private(set) var todaySteps = 0

  var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

  func requestAuthorization() async {
    guard isAvailable else { return }
    guard let steps = HKObjectType.quantityType(forIdentifier: .stepCount) else { return }
    do {
      try await store.requestAuthorization(toShare: [], read: [steps])
      authorized = true
      await refreshAndIngest()
    } catch {
      print("[healthkit] auth: \(error.localizedDescription)")
    }
  }

  func refreshAndIngest() async {
    guard isAvailable, let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
    let cal = Calendar.current
    let start = cal.startOfDay(for: Date())
    let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

    let steps: Int = await withCheckedContinuation { cont in
      let query = HKStatisticsQuery(
        quantityType: stepsType,
        quantitySamplePredicate: predicate,
        options: .cumulativeSum
      ) { _, stats, _ in
        let value = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
        cont.resume(returning: Int(value.rounded()))
      }
      store.execute(query)
    }

    todaySteps = steps
    guard SupabaseConfig.isConfigured, KeychainStore.get(.supabaseAccess) != nil else { return }
    do {
      let result = try await SupabaseClient.shared.ingestSteps(steps)
      if result.energyDelta > 0 {
        print("[healthkit] +\(result.energyDelta) energy from steps (total \(result.energy))")
      }
    } catch {
      print("[healthkit] ingest: \(error.localizedDescription)")
    }
  }
}
