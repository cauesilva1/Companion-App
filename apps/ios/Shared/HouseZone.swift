import Foundation

/// Cômodo / zona lógica da planta virtual (preparação — UI de mapa vem depois).
struct HouseZone: Codable, Identifiable, Equatable, Sendable {
  var id: String
  var name: String
  /// living | bedroom | kitchen | desk | outdoor | other
  var kind: String
  /// SSID Wi‑Fi opcional para inferir presença futura.
  var ssidHint: String?
  /// ID lógico do cômodo (futuro: beacon / rede / mapa).
  var controllerId: String?
  var sortOrder: Int

  static let defaults: [HouseZone] = [
    HouseZone(id: "zone_living", name: "Sala do Sofá", kind: "living", ssidHint: nil, controllerId: nil, sortOrder: 0),
    HouseZone(id: "zone_bedroom", name: "Quarto", kind: "bedroom", ssidHint: nil, controllerId: nil, sortOrder: 1),
    HouseZone(id: "zone_desk", name: "Mesa", kind: "desk", ssidHint: nil, controllerId: nil, sortOrder: 2),
    HouseZone(id: "zone_kitchen", name: "Cozinha", kind: "kitchen", ssidHint: nil, controllerId: nil, sortOrder: 3),
  ]
}

/// Persistência local das zonas + zona ativa (SSID / controller no futuro).
enum HouseZoneStore {
  private static let zonesKey = "companion.house.zones.v1"
  private static let activeKey = "companion.house.activeZone.v1"

  private static let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    return e
  }()

  private static let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
  }()

  static func ensureSeeded() {
    if loadZones().isEmpty {
      saveZones(HouseZone.defaults)
      if activeZoneId() == nil {
        setActiveZoneId(HouseZone.defaults.first?.id)
      }
    }
  }

  static func loadZones() -> [HouseZone] {
    let data = CompanionAppGroup.defaults.data(forKey: zonesKey)
      ?? UserDefaults.standard.data(forKey: zonesKey)
    guard let data,
          let zones = try? decoder.decode([HouseZone].self, from: data)
    else { return [] }
    return zones.sorted { $0.sortOrder < $1.sortOrder }
  }

  static func saveZones(_ zones: [HouseZone]) {
    guard let data = try? encoder.encode(zones) else { return }
    CompanionAppGroup.defaults.set(data, forKey: zonesKey)
    UserDefaults.standard.set(data, forKey: zonesKey)
  }

  static func activeZoneId() -> String? {
    CompanionAppGroup.defaults.string(forKey: activeKey)
      ?? UserDefaults.standard.string(forKey: activeKey)
  }

  static func setActiveZoneId(_ id: String?) {
    CompanionAppGroup.defaults.set(id, forKey: activeKey)
    UserDefaults.standard.set(id, forKey: activeKey)
  }

  static func activeZone() -> HouseZone? {
    let id = activeZoneId()
    let zones = loadZones()
    if let id, let hit = zones.first(where: { $0.id == id }) { return hit }
    return zones.first
  }

  /// Resolve zona ativa a partir de dicas futuras (SSID / device).
  static func resolveActiveZone(ssid: String? = nil, controllerId: String? = nil) -> HouseZone? {
    ensureSeeded()
    let zones = loadZones()
    if let controllerId, let hit = zones.first(where: { $0.controllerId == controllerId }) {
      setActiveZoneId(hit.id)
      return hit
    }
    if let ssid, let hit = zones.first(where: { $0.ssidHint == ssid }) {
      setActiveZoneId(hit.id)
      return hit
    }
    return activeZone()
  }
}
