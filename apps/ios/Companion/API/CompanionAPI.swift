import Foundation

enum APIConfig {
  /// Cloud hospedada — override via Settings / App Group.
  static let defaultCloudURL = "https://companion-engine.up.railway.app"

  static var baseURL: URL {
    if CompanionSnapshotStore.useLanAPI(),
       let stored = CompanionSnapshotStore.savedApiBase(),
       let url = URL(string: stored), !stored.isEmpty {
      return url
    }
    if let cloud = CompanionSnapshotStore.savedCloudApiBase(),
       let url = URL(string: cloud), !cloud.isEmpty {
      return url
    }
    return URL(string: defaultCloudURL)!
  }

  static func setBaseURL(_ string: String) {
    CompanionSnapshotStore.saveApiBase(string)
  }

  static func setCloudBaseURL(_ string: String) {
    CompanionSnapshotStore.saveCloudApiBase(string)
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

struct AuthResponseDTO: Decodable {
  let token: String
  let user: AuthUserDTO
}

struct AuthUserDTO: Decodable {
  let id: String
  let email: String
}

struct MissionDTO: Decodable, Identifiable {
  let id: String
  let kind: String
  let title: String
  let description: String
  let target: Int
  let progress: Int
  let rewardEnergy: Int
  let rewardAffection: Int
  let claimed: Bool
  let complete: Bool
}

struct MissionsTodayDTO: Decodable {
  let dayKey: String?
  let missions: [MissionDTO]
}

enum CompanionAPIError: LocalizedError {
  case badURL
  case http(Int, String?)
  case decoding
  case empty
  case unauthorized

  var errorDescription: String? {
    switch self {
    case .badURL: return "URL da API inválida"
    case .http(let code, let body): return body ?? "API respondeu \(code)"
    case .decoding: return "Resposta inválida da API"
    case .empty: return "Sem companion — faça o quiz ou entre na conta"
    case .unauthorized: return "Faça login com email e senha"
    }
  }
}

actor CompanionAPI {
  static let shared = CompanionAPI()

  private func authedRequest(url: URL, method: String = "GET", body: [String: Any]? = nil) throws -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token = KeychainStore.authToken {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    if let body {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    return request
  }

  private func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw CompanionAPIError.badURL }
    return (data, http)
  }

  func health() async throws -> Bool {
    let url = APIConfig.baseURL.appendingPathComponent("health")
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw CompanionAPIError.http((response as? HTTPURLResponse)?.statusCode ?? 0, nil)
    }
    return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["ok"] as? Bool == true
  }

  func register(email: String, password: String) async throws -> AuthResponseDTO {
    let url = APIConfig.baseURL.appendingPathComponent("auth/register")
    let request = try authedRequest(url: url, method: "POST", body: [
      "email": email,
      "password": password,
    ])
    let (data, http) = try await data(for: request)
    guard (200..<300).contains(http.statusCode) else {
      throw CompanionAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return try JSONDecoder().decode(AuthResponseDTO.self, from: data)
  }

  func login(email: String, password: String) async throws -> AuthResponseDTO {
    let url = APIConfig.baseURL.appendingPathComponent("auth/login")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "email": email,
      "password": password,
    ])
    let (data, http) = try await data(for: request)
    guard (200..<300).contains(http.statusCode) else {
      throw CompanionAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return try JSONDecoder().decode(AuthResponseDTO.self, from: data)
  }

  func createCompanion(body: [String: Any]) async throws -> CompanionSnapshot {
    let url = APIConfig.baseURL.appendingPathComponent("companion")
    let request = try authedRequest(url: url, method: "POST", body: body)
    let (data, http) = try await data(for: request)
    if http.statusCode == 401 { throw CompanionAPIError.unauthorized }
    guard (200..<300).contains(http.statusCode) else {
      throw CompanionAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    let dto = try decodeState(data)
    return snapshot(from: dto)
  }

  func fetchMe() async throws -> CompanionSnapshot {
    let url = APIConfig.baseURL.appendingPathComponent("companion/me")
    let request = try authedRequest(url: url)
    let (data, http) = try await data(for: request)
    if http.statusCode == 401 { throw CompanionAPIError.unauthorized }
    if http.statusCode == 404 { throw CompanionAPIError.empty }
    guard (200..<300).contains(http.statusCode) else {
      throw CompanionAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    let dto = try decodeState(data)
    return snapshot(from: dto)
  }

  /// Lista companions do modo mock (`GET /companion/export`) ou usa id salvo.
  func resolveCompanionId() async throws -> String {
    if let saved = CompanionSnapshotStore.savedCompanionId(),
       !saved.isEmpty, saved != "demo" {
      return saved
    }
    let exportURL = APIConfig.baseURL.appendingPathComponent("companion/export")
    if let (data, response) = try? await URLSession.shared.data(from: exportURL),
       let http = response as? HTTPURLResponse,
       (200..<300).contains(http.statusCode),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let list = json["companions"] as? [[String: Any]],
       let first = list.first,
       let id = first["id"] as? String {
      CompanionSnapshotStore.saveCompanionId(id)
      return id
    }
    throw CompanionAPIError.empty
  }

  func fetchState(id: String) async throws -> CompanionSnapshot {
    let url = APIConfig.baseURL.appendingPathComponent("companion/\(id)/state")
    let request = try authedRequest(url: url)
    let (data, http) = try await data(for: request)
    if http.statusCode == 401 { throw CompanionAPIError.unauthorized }
    guard (200..<300).contains(http.statusCode) else {
      throw CompanionAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    let dto = try decodeState(data)
    return snapshot(from: dto)
  }

  func interact(id: String, type: String, message: String? = nil) async throws -> (CompanionSnapshot, String?) {
    let url = APIConfig.baseURL.appendingPathComponent("companion/\(id)/interact")
    var body: [String: Any] = ["type": type]
    if let message, !message.isEmpty {
      body["message"] = message
    }
    let request = try authedRequest(url: url, method: "POST", body: body)
    let (data, http) = try await data(for: request)
    if http.statusCode == 401 { throw CompanionAPIError.unauthorized }
    guard (200..<300).contains(http.statusCode) else {
      throw CompanionAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    let decoded = try JSONDecoder().decode(InteractResponseDTO.self, from: data)
    return (snapshot(from: decoded.companion), decoded.reaction)
  }

  func missionsToday() async throws -> [LocalMission] {
    let url = APIConfig.baseURL.appendingPathComponent("missions/today")
    let request = try authedRequest(url: url)
    let (data, http) = try await data(for: request)
    if http.statusCode == 401 { throw CompanionAPIError.unauthorized }
    guard (200..<300).contains(http.statusCode) else {
      throw CompanionAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    let dto = try JSONDecoder().decode(MissionsTodayDTO.self, from: data)
    return dto.missions.map {
      LocalMission(
        id: $0.id,
        kind: $0.kind,
        title: $0.title,
        description: $0.description,
        target: $0.target,
        progress: $0.progress,
        rewardEnergy: $0.rewardEnergy,
        rewardAffection: $0.rewardAffection,
        claimed: $0.claimed
      )
    }
  }

  func claimMission(id: String) async throws -> (energy: Double, affection: Double)? {
    let url = APIConfig.baseURL.appendingPathComponent("missions/\(id)/claim")
    let request = try authedRequest(url: url, method: "POST", body: [:])
    let (data, http) = try await data(for: request)
    guard (200..<300).contains(http.statusCode) else {
      throw CompanionAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
       let companion = json["companion"] as? [String: Any] {
      let energy = (companion["energy"] as? Double) ?? Double(companion["energy"] as? Int ?? 0)
      let affection = (companion["affection"] as? Double) ?? Double(companion["affection"] as? Int ?? 0)
      return (energy, affection)
    }
    return nil
  }

  func openApp() async throws {
    let url = APIConfig.baseURL.appendingPathComponent("missions/open-app")
    let request = try authedRequest(url: url, method: "POST", body: [:])
    _ = try await data(for: request)
  }

  private func decodeState(_ data: Data) throws -> CompanionStateDTO {
    if let wrapped = try? JSONDecoder().decode(InteractResponseDTO.self, from: data) {
      return wrapped.companion
    }
    if let dto = try? JSONDecoder().decode(CompanionStateDTO.self, from: data) {
      return dto
    }
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
