import Foundation

/// Estados contextuais de vida (cloud-authoritative via `companion_ingest_context`).
enum CompanionLifeMode: String, Codable, Sendable {
  case work
  case indoor
  case sleep

  /// Hora local de dormir / acordar (relógio do aparelho / fuso do usuário).
  static let bedtimeHour = 23
  static let wakeHour = 6

  static func parse(_ raw: String?) -> CompanionLifeMode {
    guard let raw else { return .indoor }
    return CompanionLifeMode(rawValue: raw.lowercased()) ?? .indoor
  }

  static var localHour: Int {
    Calendar.current.component(.hour, from: Date())
  }

  /// Ainda é madrugada: dormindo / sonolento (antes das 6h).
  var isPreWakeDrowsy: Bool {
    self == .sleep && Self.localHour < Self.wakeHour
  }

  var labelPT: String {
    switch self {
    case .work: return "Trabalho / rua"
    case .indoor: return "Sofá / regenerando"
    case .sleep:
      return isPreWakeDrowsy ? "Meio dormindo" : "Sono / sonhos"
    }
  }

  /// Intervalo mínimo entre pensamentos autônomos no feed (segundos).
  var thoughtCooldownSec: TimeInterval {
    switch self {
    case .indoor: return 180
    case .work: return 240
    case .sleep: return 360
    }
  }

  /// Tom para prompts LLM / LocalVoice.
  var llmToneHint: String {
    switch self {
    case .work:
      return "Modo trabalho/rua: cansaço do dia, passos, esforço físico. Energia caindo. Sem frescura de escritório."
    case .indoor:
      return "Modo indoor/sofá: recuperando energia em casa, lazer, TV/som, regeneração passiva."
    case .sleep:
      if isPreWakeDrowsy {
        return """
        Você ainda está MEIO DORMINDO (antes das 6h). Como pessoa de verdade que acordou no meio da noite:
        voz baixa, respostas curtas, bocejo, sem empolgação. Pode papear um pouco, mas quer voltar a dormir.
        Não finja estar 100% acordado. Sem história longa.
        """
      }
      return "Modo sonhos: frases oníricas, surreais, curtas — histórias leves enquanto dorme. Sem spam."
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
