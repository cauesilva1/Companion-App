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
  /// Unix seconds; nil = legado (tentar refresh ao usar).
  var expiresAt: TimeInterval?
  var isAnonymous: Bool

  var isExpiredOrNear: Bool {
    guard let exp = expiresAt else { return true }
    return Date().timeIntervalSince1970 >= exp - 60
  }

  enum CodingKeys: String, CodingKey {
    case accessToken, refreshToken, userId, email, expiresAt, isAnonymous
  }

  init(
    accessToken: String,
    refreshToken: String,
    userId: String,
    email: String,
    expiresAt: TimeInterval?,
    isAnonymous: Bool = false
  ) {
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.userId = userId
    self.email = email
    self.expiresAt = expiresAt
    self.isAnonymous = isAnonymous
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    accessToken = try c.decode(String.self, forKey: .accessToken)
    refreshToken = try c.decode(String.self, forKey: .refreshToken)
    userId = try c.decode(String.self, forKey: .userId)
    email = try c.decode(String.self, forKey: .email)
    expiresAt = try c.decodeIfPresent(TimeInterval.self, forKey: .expiresAt)
    isAnonymous = try c.decodeIfPresent(Bool.self, forKey: .isAnonymous)
      ?? email.isEmpty
  }
}

enum SupabaseError: LocalizedError {
  case notConfigured
  case http(Int, String)
  case decoding
  case noSession
  case needsEmailConfirm
  case sessionExpired

  var errorDescription: String? {
    switch self {
    case .notConfigured: return "Supabase não embutido — rode node scripts/sync-supabase-config.mjs"
    case .http(let code, let body): return "Supabase \(code): \(body.prefix(120))"
    case .decoding: return "Resposta inválida do Supabase"
    case .noSession: return "Faça login"
    case .needsEmailConfirm: return "Confirme o email no Supabase (ou desative confirm email no dashboard)"
    case .sessionExpired: return "Sessão expirada — entre de novo"
    }
  }
}

actor SupabaseClient {
  static let shared = SupabaseClient()
  private let sessionKey = "companion.supabase.session.v1"

  func loadSession() -> SupabaseSession? {
    if let access = KeychainStore.get(.supabaseAccess),
       let refresh = KeychainStore.get(.supabaseRefresh),
       let userId = KeychainStore.get(.supabaseUserId),
       !access.isEmpty, !refresh.isEmpty {
      let email = KeychainStore.get(.supabaseEmail) ?? ""
      let exp = KeychainStore.get(.supabaseExpires).flatMap(Double.init)
      let anon = KeychainStore.get(.supabaseAnonymous) == "1"
        || email.isEmpty
        || email.lowercased().contains("anonymous")
      return SupabaseSession(
        accessToken: access,
        refreshToken: refresh,
        userId: userId,
        email: email,
        expiresAt: exp,
        isAnonymous: anon
      )
    }
    guard let data = UserDefaults.standard.data(forKey: sessionKey),
          let s = try? JSONDecoder().decode(SupabaseSession.self, from: data) else { return nil }
    // Migra para Keychain
    saveSession(s)
    return s
  }

  func saveSession(_ session: SupabaseSession?) {
    if let session {
      KeychainStore.set(.supabaseAccess, value: session.accessToken)
      KeychainStore.set(.supabaseRefresh, value: session.refreshToken)
      KeychainStore.set(.supabaseUserId, value: session.userId)
      KeychainStore.set(.supabaseEmail, value: session.email)
      KeychainStore.set(.supabaseAnonymous, value: session.isAnonymous ? "1" : "0")
      if let exp = session.expiresAt {
        KeychainStore.set(.supabaseExpires, value: String(exp))
      } else {
        KeychainStore.delete(.supabaseExpires)
      }
      if let data = try? JSONEncoder().encode(session) {
        UserDefaults.standard.set(data, forKey: sessionKey)
      }
    } else {
      KeychainStore.delete(.supabaseAccess)
      KeychainStore.delete(.supabaseRefresh)
      KeychainStore.delete(.supabaseUserId)
      KeychainStore.delete(.supabaseEmail)
      KeychainStore.delete(.supabaseExpires)
      KeychainStore.delete(.supabaseAnonymous)
      UserDefaults.standard.removeObject(forKey: sessionKey)
    }
  }

  var isLoggedIn: Bool { loadSession() != nil }

  /// Sessão utilizável (refresh se preciso). nil se precisa login de novo.
  func validSession() async -> SupabaseSession? {
    guard var session = loadSession() else { return nil }
    if !session.isExpiredOrNear { return session }
    do {
      session = try await refreshSession(session)
      return session
    } catch {
      saveSession(nil)
      return nil
    }
  }

  /// Mantém o usuário na nuvem sem pedir email: refresh ou login anônimo.
  @discardableResult
  func ensurePersistentSession() async -> SupabaseSession? {
    guard SupabaseConfig.isConfigured else { return nil }
    if let s = await validSession() { return s }
    do {
      return try await signInAnonymously()
    } catch {
      print("[supabase] anonymous failed: \(error.localizedDescription)")
      return nil
    }
  }

  /// Cria usuário anônimo (Auth → Providers → Anonymous no dashboard).
  func signInAnonymously() async throws -> SupabaseSession {
    let data = try await request(
      path: "/auth/v1/signup",
      method: "POST",
      body: ["data": [:] as [String: String]],
      token: nil,
      allowRetry: false
    )
    let session = try parseSession(data, fallbackEmail: "", forceAnonymous: true)
    saveSession(session)
    try? await upsertProfile(session)
    return session
  }

  private func refreshSession(_ session: SupabaseSession) async throws -> SupabaseSession {
    let data = try await request(
      path: "/auth/v1/token",
      method: "POST",
      body: ["refresh_token": session.refreshToken],
      query: "grant_type=refresh_token",
      token: nil,
      allowRetry: false
    )
    var next = try parseSession(
      data,
      fallbackEmail: session.email,
      forceAnonymous: session.isAnonymous
    )
    if session.isAnonymous { next.isAnonymous = true }
    saveSession(next)
    return next
  }

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
    prefer: String? = nil,
    allowRetry: Bool = true
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
    if http.statusCode == 401, allowRetry, let current = loadSession() {
      let refreshed = try await refreshSession(current)
      return try await request(
        path: path,
        method: method,
        body: body,
        query: query,
        token: refreshed.accessToken,
        prefer: prefer,
        allowRetry: false
      )
    }
    guard (200..<300).contains(http.statusCode) else {
      if http.statusCode == 401 {
        saveSession(nil)
        throw SupabaseError.sessionExpired
      }
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

  private func parseSession(
    _ data: Data,
    fallbackEmail: String,
    forceAnonymous: Bool = false
  ) throws -> SupabaseSession {
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let access = json["access_token"] as? String,
          let refresh = json["refresh_token"] as? String
    else { throw SupabaseError.decoding }
    let user = json["user"] as? [String: Any]
    guard let userId = user?["id"] as? String ?? json["id"] as? String else {
      throw SupabaseError.decoding
    }
    let email = (user?["email"] as? String) ?? fallbackEmail
    let expiresIn = (json["expires_in"] as? Double)
      ?? (json["expires_in"] as? Int).map(Double.init)
      ?? 3600
    let isAnonymous = forceAnonymous
      || (user?["is_anonymous"] as? Bool == true)
      || email.isEmpty
    return SupabaseSession(
      accessToken: access,
      refreshToken: refresh,
      userId: userId,
      email: email,
      expiresAt: Date().timeIntervalSince1970 + expiresIn,
      isAnonymous: isAnonymous
    )
  }

  private func requireSession() async throws -> SupabaseSession {
    if let s = await validSession() { return s }
    throw SupabaseError.noSession
  }

  private func upsertProfile(_ session: SupabaseSession) async throws {
    let email = session.email.isEmpty
      ? "anon-\(session.userId)@anonymous.local"
      : session.email
    _ = try await request(
      path: "/rest/v1/Profile",
      method: "POST",
      body: ["id": session.userId, "email": email],
      token: session.accessToken,
      prefer: "resolution=merge-duplicates,return=minimal"
    )
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
    let session = try await requireSession()
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
    let session = try await requireSession()
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
    let session = try await requireSession()
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
    let session = try await requireSession()
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
    let session = try await requireSession()
    var remote = try await fetchMissions(dayKey: dayKey)
    let localKinds = Set(missions.map(\.kind))
    let remoteKinds = Set(remote.map(\.kind))

    // Set do dia diferente (ou vazio): substitui remoto pelo catálogo local.
    if remote.isEmpty || localKinds != remoteKinds {
      for r in remote {
        _ = try await request(
          path: "/rest/v1/UserMissionProgress",
          method: "DELETE",
          query: "id=eq.\(r.id)",
          token: session.accessToken,
          prefer: "return=minimal"
        )
      }
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
    } else {
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
      remote = try await fetchMissions(dayKey: dayKey)
    }

    // Devolve set local (títulos/targets do dia) + ids/progress do remoto.
    // Nunca zera progress local se o remoto vier atrasado.
    let merged = missions.map { m -> LocalMission in
      let hit = remote.first(where: { $0.kind == m.kind })
      let progress = max(m.progress, hit?.progress ?? 0)
      return LocalMission(
        id: hit?.id ?? m.id,
        kind: m.kind,
        title: m.title,
        description: m.description,
        target: m.target,
        progress: progress,
        rewardEnergy: m.rewardEnergy,
        rewardAffection: m.rewardAffection,
        claimed: m.claimed || (hit?.claimed ?? false)
      )
    }
    return merged
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
      updatedAt: Date(),
      growthStage: "baby",
      createdAt: nil
    )
  }
}
