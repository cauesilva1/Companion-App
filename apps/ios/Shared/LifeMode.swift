import Foundation

/// Estados contextuais de vida (cloud-authoritative via `companion_ingest_context`).
enum CompanionLifeMode: String, Codable, Sendable {
  case work
  case indoor
  case sleep

  static func parse(_ raw: String?) -> CompanionLifeMode {
    guard let raw else { return .indoor }
    return CompanionLifeMode(rawValue: raw.lowercased()) ?? .indoor
  }

  var labelPT: String {
    switch self {
    case .work: return "Trabalho / campo"
    case .indoor: return "Sofá / lazer"
    case .sleep: return "Sono / hibernação"
    }
  }

  /// Tom para prompts LLM / LocalVoice.
  var llmToneHint: String {
    switch self {
    case .work:
      return "Modo trabalho/campo: tom de esforço físico, resistência e dia na rua. Sem frescura de escritório de TI."
    case .indoor:
      return "Modo indoor/sofá: recuperação, ociosidade na sala/TV, entretenimento e presença em casa."
    case .sleep:
      return "Modo sono: silêncio, hibernação. Frases curtas ou pensamento matinal guardado."
    }
  }
}

enum LifeModeStore {
  private static let key = "companion.lifeMode.v1"
  private static let homeSsidKey = "companion.homeWifiSsid.v1"
  private static let xboxKey = "companion.xboxGamertag.v1"
  private static let morningKey = "companion.morningThought.v1"

  static func saveMode(_ mode: CompanionLifeMode) {
    CompanionAppGroup.defaults.set(mode.rawValue, forKey: key)
    UserDefaults.standard.set(mode.rawValue, forKey: key)
  }

  static func loadMode() -> CompanionLifeMode {
    let raw = CompanionAppGroup.defaults.string(forKey: key)
      ?? UserDefaults.standard.string(forKey: key)
    return CompanionLifeMode.parse(raw)
  }

  static var homeWifiSsid: String? {
    get {
      let s = CompanionAppGroup.defaults.string(forKey: homeSsidKey)
        ?? UserDefaults.standard.string(forKey: homeSsidKey)
      let t = s?.trimmingCharacters(in: .whitespacesAndNewlines)
      return (t?.isEmpty == false) ? t : nil
    }
    set {
      CompanionAppGroup.defaults.set(newValue, forKey: homeSsidKey)
      UserDefaults.standard.set(newValue, forKey: homeSsidKey)
    }
  }

  static var xboxGamertag: String? {
    get {
      let s = CompanionAppGroup.defaults.string(forKey: xboxKey)
        ?? UserDefaults.standard.string(forKey: xboxKey)
      let t = s?.trimmingCharacters(in: .whitespacesAndNewlines)
      return (t?.isEmpty == false) ? t : nil
    }
    set {
      CompanionAppGroup.defaults.set(newValue, forKey: xboxKey)
      UserDefaults.standard.set(newValue, forKey: xboxKey)
    }
  }

  static var pendingMorningThought: String? {
    get {
      CompanionAppGroup.defaults.string(forKey: morningKey)
        ?? UserDefaults.standard.string(forKey: morningKey)
    }
    set {
      CompanionAppGroup.defaults.set(newValue, forKey: morningKey)
      UserDefaults.standard.set(newValue, forKey: morningKey)
    }
  }
}
