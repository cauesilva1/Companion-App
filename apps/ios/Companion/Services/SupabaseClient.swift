import Foundation

/// Cliente REST do Supabase (Auth + PostgREST) — sync sem Express.
/// URL + anon key vêm do Info.plist (gerado do .env via scripts/sync-supabase-config.mjs).
enum SupabaseConfig {
  static var url: String {
    if let s = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
       !s.isEmpty, !s.contains("PROJECT"), s.hasPrefix("http") {
      return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return ""
  }

  static var anonKey: String {
    if let s = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
       !s.isEmpty, s.hasPrefix("eyJ") {
      return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return ""
  }

  static var isConfigured: Bool {
    url.hasPrefix("http") && anonKey.count > 20
  }
}

struct SupabaseSession: Codable, Equatable {
  var accessToken: String
  var refreshToken: String
  var userId: String
  var email: String
}

enum SupabaseError: LocalizedError {
  case notConfigured
  case http(Int, String)
  case decoding
  case noSession
  case needsEmailConfirm

  var errorDescription: String? {
    switch self {
    case .notConfigured: return "Supabase não embutido — rode node scripts/sync-supabase-config.mjs"
    case .http(let code, let body): return "Supabase \(code): \(body.prefix(120))"
    case .decoding: return "Resposta inválida do Supabase"
    case .noSession: return "Faça login"
    case .needsEmailConfirm: return "Confirme o email no Supabase (ou desative confirm email no dashboard)"
    }
  }
}

actor SupabaseClient {
  static let shared = SupabaseClient()
  private let sessionKey = "companion.supabase.session.v1"

  func loadSession() -> SupabaseSession? {
    guard let data = UserDefaults.standard.data(forKey: sessionKey) else { return nil }
    return try? JSONDecoder().decode(SupabaseSession.self, from: data)
  }

  func saveSession(_ session: SupabaseSession?) {
    if let session, let data = try? JSONEncoder().encode(session) {
      UserDefaults.standard.set(data, forKey: sessionKey)
    } else {
      UserDefaults.standard.removeObject(forKey: sessionKey)
    }
  }

  var isLoggedIn: Bool { loadSession() != nil }

  private func baseURL() throws -> URL {
    guard SupabaseConfig.isConfigured, let url = URL(string: SupabaseConfig.url) else {
      throw SupabaseError.notConfigured
    }
    return url
  }

  private func authHeaders(token: String? = nil) -> [String: String] {
    var h = [
      "apikey": SupabaseConfig.anonKey,
      "Content-Type": "application/json",
    ]
    h["Authorization"] = "Bearer \(token ?? SupabaseConfig.anonKey)"
    return h
  }

  private func request(
    path: String,
    method: String,
    body: [String: Any]? = nil,
    query: String = "",
    token: String? = nil,
    prefer: String? = nil
  ) async throws -> Data {
    let root = try baseURL()
    var urlString = root.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    urlString += path
    if !query.isEmpty { urlString += "?\(query)" }
    guard let url = URL(string: urlString) else { throw SupabaseError.notConfigured }
    var req = URLRequest(url: url)
    req.httpMethod = method
    for (k, v) in authHeaders(token: token) {
      req.setValue(v, forHTTPHeaderField: k)
    }
    if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
    if let body {
      req.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse else { throw SupabaseError.decoding }
    guard (200..<300).contains(http.statusCode) else {
      throw SupabaseError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
    }
    return data
  }

  func signUp(email: String, password: String) async throws -> SupabaseSession {
    let data = try await request(
      path: "/auth/v1/signup",
      method: "POST",
      body: ["email": email, "password": password]
    )
    if let session = try? parseSession(data, fallbackEmail: email) {
      saveSession(session)
      try? await upsertProfile(session)
      return session
    }
    // Sem tokens = confirme email no dashboard, ou tente login imediato
    do {
      return try await signIn(email: email, password: password)
    } catch {
      throw SupabaseError.needsEmailConfirm
    }
  }

  func signIn(email: String, password: String) async throws -> SupabaseSession {
    let data = try await request(
      path: "/auth/v1/token",
      method: "POST",
      body: ["email": email, "password": password],
      query: "grant_type=password"
    )
    let session = try parseSession(data, fallbackEmail: email)
    saveSession(session)
    try? await upsertProfile(session)
    return session
  }

  func signOut() {
    saveSession(nil)
  }

  private func parseSession(_ data: Data, fallbackEmail: String) throws -> SupabaseSession {
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let access = json["access_token"] as? String,
          let refresh = json["refresh_token"] as? String
    else { throw SupabaseError.decoding }
    let user = json["user"] as? [String: Any]
    guard let userId = user?["id"] as? String ?? json["id"] as? String else {
      throw SupabaseError.decoding
    }
    let email = (user?["email"] as? String) ?? fallbackEmail
    return SupabaseSession(
      accessToken: access,
      refreshToken: refresh,
      userId: userId,
      email: email
    )
  }

  private func upsertProfile(_ session: SupabaseSession) async throws {
    _ = try await request(
      path: "/rest/v1/Profile",
      method: "POST",
      body: ["id": session.userId, "email": session.email],
      token: session.accessToken,
      prefer: "resolution=merge-duplicates,return=minimal"
    )
  }

  private func requireSession() throws -> SupabaseSession {
    guard let s = loadSession() else { throw SupabaseError.noSession }
    return s
  }

  struct RemoteCompanion: Codable {
    var id: String
    var userId: String
    var name: String
    var personality: String
    var skin: String
    var artStyle: String
    var backdrop: String
    var archetype: String
    var mood: String
    var energy: Int
    var affection: Int
  }

  func fetchMyCompanion() async throws -> CompanionSnapshot? {
    let session = try requireSession()
    let data = try await request(
      path: "/rest/v1/Companion",
      method: "GET",
      query: "userId=eq.\(session.userId)&order=createdAt.asc&limit=1",
      token: session.accessToken
    )
    let rows = try JSONDecoder().decode([RemoteCompanion].self, from: data)
    guard let row = rows.first else { return nil }
    return snapshot(from: row)
  }

  func upsertCompanion(_ snap: CompanionSnapshot, personality: String? = nil) async throws -> CompanionSnapshot {
    let session = try requireSession()
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    let now = iso.string(from: Date())

    if let existing = try await fetchMyCompanion() {
      let body: [String: Any] = [
        "name": snap.name,
        "skin": snap.skin,
        "archetype": snap.archetype,
        "mood": snap.mood.uppercased(),
        "energy": Int(snap.energy.rounded()),
        "affection": Int(snap.affection.rounded()),
        "personality": personality ?? snap.archetype,
        "lastDecayAt": now,
        "lastInteractionAt": now,
      ]
      _ = try await request(
        path: "/rest/v1/Companion",
        method: "PATCH",
        body: body,
        query: "id=eq.\(existing.id)",
        token: session.accessToken,
        prefer: "return=minimal"
      )
      var out = snap
      out.id = existing.id
      return out
    }

    let id = snap.id == "demo" ? "cmp_\(UUID().uuidString.prefix(12))" : snap.id
    let body: [String: Any] = [
      "id": id,
      "userId": session.userId,
      "name": snap.name,
      "personality": personality ?? snap.archetype,
      "skin": snap.skin,
      "artStyle": "pixel",
      "backdrop": "sky",
      "archetype": snap.archetype,
      "mood": snap.mood.uppercased(),
      "energy": Int(snap.energy.rounded()),
      "affection": Int(snap.affection.rounded()),
      "lastDecayAt": now,
      "lastInteractionAt": now,
      "memoryNotes": [] as [String],
    ]
    let data = try await request(
      path: "/rest/v1/Companion",
      method: "POST",
      body: body,
      token: session.accessToken,
      prefer: "return=representation"
    )
    if let rows = try? JSONDecoder().decode([RemoteCompanion].self, from: data), let row = rows.first {
      return snapshot(from: row)
    }
    var out = snap
    out.id = id
    return out
  }

  func pushCompanionState(_ snap: CompanionSnapshot) async throws {
    let session = try requireSession()
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    let body: [String: Any] = [
      "name": snap.name,
      "skin": snap.skin,
      "archetype": snap.archetype,
      "mood": snap.mood.uppercased(),
      "energy": Int(snap.energy.rounded()),
      "affection": Int(snap.affection.rounded()),
      "personality": snap.archetype,
      "lastInteractionAt": iso.string(from: Date()),
    ]
    _ = try await request(
      path: "/rest/v1/Companion",
      method: "PATCH",
      body: body,
      query: "id=eq.\(snap.id)",
      token: session.accessToken,
      prefer: "return=minimal"
    )
  }

  struct RemoteMission: Codable {
    var id: String
    var userId: String
    var dayKey: String
    var kind: String
    var title: String
    var description: String
    var target: Int
    var progress: Int
    var rewardEnergy: Int
    var rewardAffection: Int
    var claimed: Bool
  }

  func fetchMissions(dayKey: String) async throws -> [LocalMission] {
    let session = try requireSession()
    let data = try await request(
      path: "/rest/v1/UserMissionProgress",
      method: "GET",
      query: "userId=eq.\(session.userId)&dayKey=eq.\(dayKey)",
      token: session.accessToken
    )
    let rows = try JSONDecoder().decode([RemoteMission].self, from: data)
    return rows.map {
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

  func syncMissions(_ missions: [LocalMission], dayKey: String) async throws -> [LocalMission] {
    let session = try requireSession()
    var remote = try await fetchMissions(dayKey: dayKey)
    if remote.isEmpty {
      for m in missions {
        let id = "msn_\(dayKey)_\(m.kind)_\(String(session.userId.prefix(8)))"
        let body: [String: Any] = [
          "id": id,
          "userId": session.userId,
          "dayKey": dayKey,
          "kind": m.kind,
          "title": m.title,
          "description": m.description,
          "target": m.target,
          "progress": m.progress,
          "rewardEnergy": m.rewardEnergy,
          "rewardAffection": m.rewardAffection,
          "claimed": m.claimed,
        ]
        _ = try await request(
          path: "/rest/v1/UserMissionProgress",
          method: "POST",
          body: body,
          token: session.accessToken,
          prefer: "return=minimal"
        )
      }
      remote = try await fetchMissions(dayKey: dayKey)
      return remote.isEmpty ? missions : remote
    }
    // Merge: take max progress / claimed from local
    for m in missions {
      guard let hit = remote.first(where: { $0.kind == m.kind }) else { continue }
      let progress = max(hit.progress, m.progress)
      let claimed = hit.claimed || m.claimed
      if progress != hit.progress || claimed != hit.claimed {
        _ = try await request(
          path: "/rest/v1/UserMissionProgress",
          method: "PATCH",
          body: ["progress": progress, "claimed": claimed],
          query: "id=eq.\(hit.id)",
          token: session.accessToken,
          prefer: "return=minimal"
        )
      }
    }
    return try await fetchMissions(dayKey: dayKey)
  }

  private func snapshot(from row: RemoteCompanion) -> CompanionSnapshot {
    CompanionSnapshot(
      id: row.id,
      name: row.name,
      mood: row.mood,
      moodText: MoodEngine.moodText(name: row.name, mood: CompanionMood(rawValue: row.mood) ?? .CONTENT),
      energy: Double(row.energy),
      affection: Double(row.affection),
      skin: row.skin,
      archetype: row.archetype,
      updatedAt: Date()
    )
  }
}
