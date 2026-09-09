import Foundation
import SwiftUI

/// Chaves compartilhadas entre app, widget e Live Activity (App Group).
enum CompanionAppGroup {
  static let id = "group.com.companion.tamagotchi"
  static let snapshotKey = "companion.snapshot.v1"
  static let companionIdKey = "companion.id"
  static let apiBaseKey = "companion.apiBase"
  static let cloudApiBaseKey = "companion.cloudApiBase"
  static let useLanAPIKey = "companion.useLanAPI"
  /// Chave leve só pro widget (evita depender do decode do snapshot completo).
  static let weatherConditionKey = "companion.weatherCondition.v1"
  static let weatherTempCKey = "companion.weatherTempC.v1"
  static let weatherAtKey = "companion.weatherAt.v1"
  static let skyPeriodKey = "companion.skyPeriod.v1"
  static let weatherLatKey = "companion.weatherLat.v1"
  static let weatherLonKey = "companion.weatherLon.v1"
  static let weatherFileName = "companion-weather.json"

  /// Container real do App Group (nil se o entitlement não provisionou).
  static var containerURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
  }

  /// Personal Team às vezes devolve suite “fantasma” — sempre espelha no standard também.
  static var defaults: UserDefaults {
    UserDefaults(suiteName: id) ?? .standard
  }

  static var usesAppGroup: Bool {
    containerURL != nil
  }

  static func writeAll(_ block: (UserDefaults) -> Void) {
    block(defaults)
    block(.standard)
    defaults.synchronize()
    UserDefaults.standard.synchronize()
  }
}

struct CompanionSnapshot: Codable, Equatable, Sendable {
  var id: String
  var name: String
  var mood: String
  var moodText: String
  var energy: Double
  var affection: Double
  var skin: String
  var archetype: String
  var updatedAt: Date
  /// baby | teen | adult — opcional para snapshots antigos
  var growthStage: String?
  var createdAt: Date?
  /// present | away | expedition — espelho do lifeMode (indoor/work/sleep)
  var presenceStatus: String?
  var decayFrozen: Bool?
  /// work | indoor | sleep (cloud life mode)
  var lifeMode: String?
  var gamingStatus: String?
  var mediaHint: String?
  var morningThought: String?
  /// Título de convivência (ex.: Rei do Sofá).
  var activeTitle: String?
  var titleKey: String?
  var equippedTitleKey: String?
  /// sunny | rainy | snowy | cloudy | night
  var weatherCondition: String? = nil
  var weatherTempC: Int? = nil
  /// Plate do céu que o app está mostrando — widget DEVE espelhar isto.
  /// dawn | day | evening | night | storm | cloudy | snowy
  var skyPeriodRaw: String? = nil

  static let demo = CompanionSnapshot(
    id: "demo",
    name: "zezinho",
    mood: "HAPPY",
    moodText: "zezinho está feliz",
    energy: 72,
    affection: 80,
    skin: "dino-mort",
    archetype: "zoeiro",
    updatedAt: Date(),
    growthStage: "baby",
    createdAt: Date(),
    presenceStatus: "present",
    decayFrozen: false,
    lifeMode: "indoor",
    gamingStatus: nil,
    mediaHint: nil,
    morningThought: nil,
    activeTitle: "Recém-chegado",
    titleKey: "newcomer",
    equippedTitleKey: "newcomer",
    weatherCondition: nil,
    weatherTempC: nil,
    skyPeriodRaw: nil
  )

  /// Céu autoritativo: weather do snapshot (o que o app usa) → plate gravado → hora.
  var resolvedSkyPeriod: SkyPeriod {
    if let w = weatherCondition, !w.isEmpty {
      return SkyPeriod.from(weather: w)
    }
    if let raw = skyPeriodRaw, let period = SkyPeriod(rawValue: raw) {
      return period
    }
    return SkyPeriod.current()
  }

  /// Placeholder de UI — nunca sincronizar / nunca preferir sobre pet real.
  var isDemoPlaceholder: Bool {
    id == "demo" || id.isEmpty || name.lowercased() == "zezinho"
  }

  var energyPercent: Int { Int(energy.rounded()) }
  var affectionPercent: Int { Int(affection.rounded()) }

  var normalizedGrowthStage: GrowthStage {
    Growth.effective(growthStage)
  }

  var moodEmoji: String {
    switch mood.uppercased() {
    case "EXCITED": return "✨"
    case "HAPPY": return "😊"
    case "CONTENT": return "😌"
    case "BORED": return "😐"
    case "SLEEPY": return "😴"
    case "SAD": return "😢"
    case "LONELY": return "🥺"
    default: return "🦕"
    }
  }

  /// Nome do imageset em Media.xcassets
  var dinoImageName: String {
    Self.imageName(forSkin: skin)
  }

  static func imageName(forSkin skin: String) -> String {
    let key = skin.lowercased().replacingOccurrences(of: "dino-", with: "")
    switch key {
    case "doux": return "DinoDoux"
    case "vita": return "DinoVita"
    case "olaf": return "DinoOlaf"
    case "kuro": return "DinoKuro"
    case "mort": return "DinoMort"
    case "cole": return "DinoCole"
    case "kira": return "DinoKira"
    case "loki": return "DinoLoki"
    case "mono": return "DinoMono"
    case "nico": return "DinoNico"
    case "sena": return "DinoSena"
    case "tard": return "DinoTard"
    default: return "DinoMort"
    }
  }
}

enum CompanionSnapshotStore {
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

  static func save(_ snapshot: CompanionSnapshot) {
    var snapshot = snapshot
    // Garante plate no JSON compartilhado (widget lê só isto).
    if snapshot.skyPeriodRaw == nil || snapshot.skyPeriodRaw?.isEmpty == true {
      if let w = snapshot.weatherCondition, !w.isEmpty {
        snapshot.skyPeriodRaw = SkyPeriod.from(weather: w).rawValue
      }
    }
    guard let data = try? encoder.encode(snapshot) else { return }
    CompanionAppGroup.defaults.set(data, forKey: CompanionAppGroup.snapshotKey)
    CompanionAppGroup.defaults.set(snapshot.id, forKey: CompanionAppGroup.companionIdKey)
    UserDefaults.standard.set(data, forKey: CompanionAppGroup.snapshotKey)
    UserDefaults.standard.set(snapshot.id, forKey: CompanionAppGroup.companionIdKey)
    CompanionAppGroup.defaults.synchronize()
    UserDefaults.standard.synchronize()
    if let wx = snapshot.weatherCondition, !wx.isEmpty {
      saveWeather(condition: wx, tempC: snapshot.weatherTempC)
    }
    if let raw = snapshot.skyPeriodRaw, let period = SkyPeriod(rawValue: raw) {
      saveSkyPeriod(period)
    }
  }

  static func saveWeather(condition: String, tempC: Int? = nil, latitude: Double? = nil, longitude: Double? = nil) {
    let c = condition.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !c.isEmpty else { return }
    let now = Date().timeIntervalSince1970
    let sky = SkyPeriod.from(weather: c).rawValue
    CompanionAppGroup.writeAll { defaults in
      defaults.set(c, forKey: CompanionAppGroup.weatherConditionKey)
      defaults.set(sky, forKey: CompanionAppGroup.skyPeriodKey)
      if let tempC {
        defaults.set(tempC, forKey: CompanionAppGroup.weatherTempCKey)
      }
      if let latitude { defaults.set(latitude, forKey: CompanionAppGroup.weatherLatKey) }
      if let longitude { defaults.set(longitude, forKey: CompanionAppGroup.weatherLonKey) }
      defaults.set(now, forKey: CompanionAppGroup.weatherAtKey)
    }
    if let dir = CompanionAppGroup.containerURL {
      var payload: [String: Any] = [
        "condition": c,
        "sky": sky,
        "at": now,
      ]
      if let tempC { payload["tempC"] = tempC }
      if let latitude { payload["lat"] = latitude }
      if let longitude { payload["lon"] = longitude }
      if let data = try? JSONSerialization.data(withJSONObject: payload) {
        try? data.write(to: dir.appendingPathComponent(CompanionAppGroup.weatherFileName), options: .atomic)
      }
    }
  }

  static func loadWeatherCoords() -> (lat: Double, lon: Double)? {
    if let dir = CompanionAppGroup.containerURL {
      let url = dir.appendingPathComponent(CompanionAppGroup.weatherFileName)
      if let data = try? Data(contentsOf: url),
         let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let lat = json["lat"] as? Double,
         let lon = json["lon"] as? Double {
        return (lat, lon)
      }
    }
    let lat = CompanionAppGroup.defaults.object(forKey: CompanionAppGroup.weatherLatKey) as? Double
      ?? UserDefaults.standard.object(forKey: CompanionAppGroup.weatherLatKey) as? Double
    let lon = CompanionAppGroup.defaults.object(forKey: CompanionAppGroup.weatherLonKey) as? Double
      ?? UserDefaults.standard.object(forKey: CompanionAppGroup.weatherLonKey) as? Double
    if let lat, let lon { return (lat, lon) }
    return nil
  }

  /// Plate exato que o app está mostrando — widget deve espelhar isto.
  static func saveSkyPeriod(_ period: SkyPeriod) {
    CompanionAppGroup.writeAll { defaults in
      defaults.set(period.rawValue, forKey: CompanionAppGroup.skyPeriodKey)
    }
    if let dir = CompanionAppGroup.containerURL {
      let url = dir.appendingPathComponent(CompanionAppGroup.weatherFileName)
      var payload: [String: Any] = [:]
      if let data = try? Data(contentsOf: url),
         let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        payload = json
      }
      payload["sky"] = period.rawValue
      payload["at"] = Date().timeIntervalSince1970
      if let data = try? JSONSerialization.data(withJSONObject: payload) {
        try? data.write(to: url, options: .atomic)
      }
    }
  }

  static func loadSkyPeriod() -> SkyPeriod? {
    if let dir = CompanionAppGroup.containerURL {
      let url = dir.appendingPathComponent(CompanionAppGroup.weatherFileName)
      if let data = try? Data(contentsOf: url),
         let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let raw = json["sky"] as? String,
         let period = SkyPeriod(rawValue: raw) {
        return period
      }
    }
    if let raw = CompanionAppGroup.defaults.string(forKey: CompanionAppGroup.skyPeriodKey)
      ?? UserDefaults.standard.string(forKey: CompanionAppGroup.skyPeriodKey),
       let period = SkyPeriod(rawValue: raw) {
      return period
    }
    return nil
  }

  static func loadWeatherCondition() -> String? {
    // 1) Arquivo no App Group container
    if let dir = CompanionAppGroup.containerURL {
      let url = dir.appendingPathComponent(CompanionAppGroup.weatherFileName)
      if let data = try? Data(contentsOf: url),
         let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let c = json["condition"] as? String,
         !c.isEmpty {
        return c
      }
    }
    // 2) UserDefaults suite + standard
    if let c = CompanionAppGroup.defaults.string(forKey: CompanionAppGroup.weatherConditionKey), !c.isEmpty {
      return c
    }
    if let c = UserDefaults.standard.string(forKey: CompanionAppGroup.weatherConditionKey), !c.isEmpty {
      return c
    }
    // 3) Snapshot bruto
    if let data = CompanionAppGroup.defaults.data(forKey: CompanionAppGroup.snapshotKey)
      ?? UserDefaults.standard.data(forKey: CompanionAppGroup.snapshotKey),
       let snap = try? decoder.decode(CompanionSnapshot.self, from: data),
       let wx = snap.weatherCondition, !wx.isEmpty {
      return wx
    }
    return nil
  }

  static func load() -> CompanionSnapshot? {
    var snap: CompanionSnapshot?
    if let data = CompanionAppGroup.defaults.data(forKey: CompanionAppGroup.snapshotKey),
       let decoded = try? decoder.decode(CompanionSnapshot.self, from: data) {
      snap = decoded
    } else if let data = UserDefaults.standard.data(forKey: CompanionAppGroup.snapshotKey),
              let decoded = try? decoder.decode(CompanionSnapshot.self, from: data) {
      snap = decoded
    }
    guard var result = snap else { return nil }
    if result.weatherCondition == nil || result.weatherCondition?.isEmpty == true,
       let wx = loadWeatherCondition(), !wx.isEmpty {
      result.weatherCondition = wx
    }
    if result.skyPeriodRaw == nil || result.skyPeriodRaw?.isEmpty == true {
      if let wx = result.weatherCondition, !wx.isEmpty {
        result.skyPeriodRaw = SkyPeriod.from(weather: wx).rawValue
      } else if let sky = loadSkyPeriod() {
        result.skyPeriodRaw = sky.rawValue
      }
    }
    return result
  }

  static func clear() {
    CompanionAppGroup.defaults.removeObject(forKey: CompanionAppGroup.snapshotKey)
    CompanionAppGroup.defaults.removeObject(forKey: CompanionAppGroup.companionIdKey)
    UserDefaults.standard.removeObject(forKey: CompanionAppGroup.snapshotKey)
    UserDefaults.standard.removeObject(forKey: CompanionAppGroup.companionIdKey)
  }

  static func savedCompanionId() -> String? {
    if let id = CompanionAppGroup.defaults.string(forKey: CompanionAppGroup.companionIdKey), !id.isEmpty {
      return id
    }
    return UserDefaults.standard.string(forKey: CompanionAppGroup.companionIdKey)
  }

  static func saveCompanionId(_ id: String) {
    CompanionAppGroup.defaults.set(id, forKey: CompanionAppGroup.companionIdKey)
    UserDefaults.standard.set(id, forKey: CompanionAppGroup.companionIdKey)
  }

  static func saveApiBase(_ base: String) {
    CompanionAppGroup.defaults.set(base, forKey: CompanionAppGroup.apiBaseKey)
    UserDefaults.standard.set(base, forKey: CompanionAppGroup.apiBaseKey)
  }

  static func savedApiBase() -> String? {
    if let s = CompanionAppGroup.defaults.string(forKey: CompanionAppGroup.apiBaseKey), !s.isEmpty {
      return s
    }
    return UserDefaults.standard.string(forKey: CompanionAppGroup.apiBaseKey)
  }

  /// Default false = cloud / standalone; LAN só em Avançado.
  static func useLanAPI() -> Bool {
    if CompanionAppGroup.defaults.object(forKey: CompanionAppGroup.useLanAPIKey) != nil {
      return CompanionAppGroup.defaults.bool(forKey: CompanionAppGroup.useLanAPIKey)
    }
    return UserDefaults.standard.bool(forKey: CompanionAppGroup.useLanAPIKey)
  }

  static func setUseLanAPI(_ value: Bool) {
    CompanionAppGroup.defaults.set(value, forKey: CompanionAppGroup.useLanAPIKey)
    UserDefaults.standard.set(value, forKey: CompanionAppGroup.useLanAPIKey)
  }

  static func saveCloudApiBase(_ base: String) {
    CompanionAppGroup.defaults.set(base, forKey: CompanionAppGroup.cloudApiBaseKey)
    UserDefaults.standard.set(base, forKey: CompanionAppGroup.cloudApiBaseKey)
  }

  static func savedCloudApiBase() -> String? {
    if let s = CompanionAppGroup.defaults.string(forKey: CompanionAppGroup.cloudApiBaseKey), !s.isEmpty {
      return s
    }
    return UserDefaults.standard.string(forKey: CompanionAppGroup.cloudApiBaseKey)
  }
}

/// Avatar do dino a partir do Asset Catalog compartilhado.
struct DinoAvatar: View {
  let skin: String
  var size: CGFloat = 96

  var body: some View {
    Image(CompanionSnapshot.imageName(forSkin: skin))
      .resizable()
      .interpolation(.none)
      .scaledToFit()
      .frame(width: size, height: size)
      .accessibilityLabel("Dino \(skin)")
  }
}
