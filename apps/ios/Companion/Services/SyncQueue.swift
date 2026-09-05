import Foundation

/// Fila de sync quando o Supabase está offline.
enum SyncQueue {
  private static let key = "companion.syncQueue.v1"

  struct Item: Codable {
    var id: String
    var kind: String // push_state | push_missions
    var payload: Data
    var createdAt: Date
  }

  static func enqueuePushState(_ snap: CompanionSnapshot) {
    guard let data = try? JSONEncoder().encode(snap) else { return }
    var q = load()
    q.removeAll { $0.kind == "push_state" }
    q.append(Item(id: UUID().uuidString, kind: "push_state", payload: data, createdAt: Date()))
    save(q)
  }

  static func enqueueMissions(_ missions: [LocalMission], dayKey: String) {
    struct Box: Codable { var dayKey: String; var missions: [LocalMission] }
    guard let data = try? JSONEncoder().encode(Box(dayKey: dayKey, missions: missions)) else { return }
    var q = load()
    q.removeAll { $0.kind == "push_missions" }
    q.append(Item(id: UUID().uuidString, kind: "push_missions", payload: data, createdAt: Date()))
    save(q)
  }

  static func flush() async {
    let q = load()
    let loggedIn = await SupabaseClient.shared.isLoggedIn
    guard !q.isEmpty, loggedIn else { return }
    var remaining: [Item] = []
    for item in q {
      do {
        switch item.kind {
        case "push_state":
          let snap = try JSONDecoder().decode(CompanionSnapshot.self, from: item.payload)
          try await SupabaseClient.shared.pushCompanionState(snap)
        case "push_missions":
          struct Box: Codable { var dayKey: String; var missions: [LocalMission] }
          let box = try JSONDecoder().decode(Box.self, from: item.payload)
          _ = try await SupabaseClient.shared.syncMissions(box.missions, dayKey: box.dayKey)
        default:
          break
        }
      } catch {
        remaining.append(item)
      }
    }
    save(remaining)
  }

  private static func load() -> [Item] {
    guard let data = UserDefaults.standard.data(forKey: key),
          let items = try? JSONDecoder().decode([Item].self, from: data) else { return [] }
    return items
  }

  private static func save(_ items: [Item]) {
    if let data = try? JSONEncoder().encode(items) {
      UserDefaults.standard.set(data, forKey: key)
    }
  }
}
