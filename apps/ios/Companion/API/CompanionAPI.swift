import Foundation

enum APIConfig {
  /// Simulador → Mac localhost. Device físico: use o IP do Mac na mesma Wi‑Fi.
  static var baseURL: URL {
    if let stored = CompanionAppGroup.defaults.string(forKey: CompanionAppGroup.apiBaseKey),
       let url = URL(string: stored), !stored.isEmpty {
      return url
    }
    #if targetEnvironment(simulator)
    return URL(string: "http://127.0.0.1:3333")!
    #else
    return URL(string: "http://127.0.0.1:3333")!
    #endif
  }

  static func setBaseURL(_ string: String) {
    CompanionAppGroup.defaults.set(string, forKey: CompanionAppGroup.apiBaseKey)
  }
}

struct CompanionStateDTO: Decodable {
  let id: String
  let name: String
  let mood: String
  let moodText: String?
  let energy: Double
  let affection: Double
  let skin: String?
  let archetype: String?
}

struct InteractResponseDTO: Decodable {
  let companion: CompanionStateDTO
  let reaction: String?
}

enum CompanionAPIError: LocalizedError {
  case badURL
  case http(Int)
  case decoding
  case empty

  var errorDescription: String? {
    switch self {
    case .badURL: return "URL da API inválida"
    case .http(let code): return "API respondeu \(code)"
    case .decoding: return "Resposta inválida da API"
    case .empty: return "Sem companion — rode o desktop/API e crie um pet"
    }
  }
}

actor CompanionAPI {
  static let shared = CompanionAPI()

  func health() async throws -> Bool {
    let url = APIConfig.baseURL.appendingPathComponent("health")
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw CompanionAPIError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
    }
    return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["ok"] as? Bool == true
  }

  /// Lista companions do modo mock (`GET /companion` se existir) ou usa id salvo.
  func resolveCompanionId() async throws -> String {
    if let saved = CompanionAppGroup.defaults.string(forKey: CompanionAppGroup.companionIdKey),
       !saved.isEmpty, saved != "demo" {
      return saved
    }
    // Fallback: tenta export / listagem se disponível
    let exportURL = APIConfig.baseURL.appendingPathComponent("companion/export")
    if let (data, response) = try? await URLSession.shared.data(from: exportURL),
       let http = response as? HTTPURLResponse,
       (200..<300).contains(http.statusCode),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let list = json["companions"] as? [[String: Any]],
       let first = list.first,
       let id = first["id"] as? String {
      CompanionAppGroup.defaults.set(id, forKey: CompanionAppGroup.companionIdKey)
      return id
    }
    throw CompanionAPIError.empty
  }

  func fetchState(id: String) async throws -> CompanionSnapshot {
    let url = APIConfig.baseURL.appendingPathComponent("companion/\(id)/state")
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let http = response as? HTTPURLResponse else { throw CompanionAPIError.badURL }
    guard (200..<300).contains(http.statusCode) else { throw CompanionAPIError.http(http.statusCode) }
    let dto = try decodeState(data)
    return snapshot(from: dto)
  }

  func interact(id: String, type: String, message: String? = nil) async throws -> (CompanionSnapshot, String?) {
    let url = APIConfig.baseURL.appendingPathComponent("companion/\(id)/interact")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    var body: [String: Any] = ["type": type]
    if let message, !message.isEmpty {
      body["message"] = message
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw CompanionAPIError.badURL }
    guard (200..<300).contains(http.statusCode) else { throw CompanionAPIError.http(http.statusCode) }
    let decoded = try JSONDecoder().decode(InteractResponseDTO.self, from: data)
    return (snapshot(from: decoded.companion), decoded.reaction)
  }

  private func decodeState(_ data: Data) throws -> CompanionStateDTO {
    if let wrapped = try? JSONDecoder().decode(InteractResponseDTO.self, from: data) {
      return wrapped.companion
    }
    if let dto = try? JSONDecoder().decode(CompanionStateDTO.self, from: data) {
      return dto
    }
    // Alguns mocks devolvem { companion: {...} }
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let companion = json["companion"] as? [String: Any] {
      let nested = try JSONSerialization.data(withJSONObject: companion)
      return try JSONDecoder().decode(CompanionStateDTO.self, from: nested)
    }
    throw CompanionAPIError.decoding
  }

  private func snapshot(from dto: CompanionStateDTO) -> CompanionSnapshot {
    CompanionSnapshot(
      id: dto.id,
      name: dto.name,
      mood: dto.mood,
      moodText: dto.moodText ?? "\(dto.name) está por aí",
      energy: dto.energy,
      affection: dto.affection,
      skin: dto.skin ?? "dino-mort",
      archetype: dto.archetype ?? "curioso",
      updatedAt: Date()
    )
  }
}
