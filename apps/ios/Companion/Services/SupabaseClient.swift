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

  /// Confirma no Auth que o user ainda existe (apagar no Dashboard invalida).
  private func assertUserExists(_ session: SupabaseSession) async throws {
    _ = try await request(
      path: "/auth/v1/user",
      method: "GET",
      token: session.accessToken,
      allowRetry: false
    )
  }

  /// Sessão utilizável: refresh se preciso + valida no servidor (com cache curto).
  private var lastUserAssertAt: TimeInterval = 0
  private var lastUserAssertId: String = ""

  func validSession() async -> SupabaseSession? {
    guard var session = loadSession() else { return nil }
    if session.isExpiredOrNear {
      do {
        session = try await refreshSession(session)
      } catch {
        saveSession(nil)
        return nil
      }
    }
    let now = Date().timeIntervalSince1970
    // Evita GET /auth/v1/user em toda chamada (login ficava lento/travado).
    if session.userId == lastUserAssertId, now - lastUserAssertAt < 45 {
      return session
    }
    do {
      try await assertUserExists(session)
      lastUserAssertAt = now
      lastUserAssertId = session.userId
      return session
    } catch {
      saveSession(nil)
      lastUserAssertAt = 0
      lastUserAssertId = ""
      return nil
    }
  }

  /// Mantém o usuário na nuvem sem pedir email: refresh/valida ou login anônimo.
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

  /// Apaga tokens do Keychain neste iPhone (não chama a API de delete user).
  func clearLocalSession() {
    saveSession(nil)
    lastUserAssertAt = 0
    lastUserAssertId = ""
  }

  /// Cria usuário anônimo (Auth → Providers → Anonymous no dashboard).
  func signInAnonymously() async throws -> SupabaseSession {
    let data = try await request(
      path: "/auth/v1/signup",
      method: "POST",
      body: [
        "data": [:] as [String: String],
        "gotrue_meta_security": [:] as [String: String],
      ],
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
    req.timeoutInterval = 20
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
    var presenceStatus: String?
    var decayFrozen: Bool?
    var growthStage: String?
    /// Presente após quiz v3; ausência = precisa refazer o questionário.
    var traits: TraitsPayload?

    struct TraitsPayload: Codable {
      var vibe: String?
      var archetype: String?
      var focus: String?
      var communicationStyle: String?
    }

    var hasQuizTraits: Bool {
      guard let traits else { return false }
      return traits.vibe != nil || traits.archetype != nil || traits.focus != nil
    }
  }

  func fetchMyCompanion() async throws -> CompanionSnapshot? {
    let details = try await fetchMyCompanionDetails()
    return details?.snapshot
  }

  func fetchMyCompanionDetails() async throws -> (snapshot: CompanionSnapshot, hasTraits: Bool)? {
    let session = try await requireSession()
    let data = try await request(
      path: "/rest/v1/Companion",
      method: "GET",
      query: "userId=eq.\(session.userId)&order=createdAt.asc&limit=1",
      token: session.accessToken
    )
    let rows = try JSONDecoder().decode([RemoteCompanion].self, from: data)
    guard let row = rows.first else { return nil }
    return (snapshot(from: row), row.hasQuizTraits)
  }

  /// Apaga todos os companions do usuário autenticado (quiz de novo / sair da conta).
  func deleteMyCompanions() async throws {
    let session = try await requireSession()
    _ = try await request(
      path: "/rest/v1/Companion",
      method: "DELETE",
      query: "userId=eq.\(session.userId)",
      token: session.accessToken,
      prefer: "return=minimal"
    )
  }

  /// Cloud-First: lê estado pós-decay via Edge Function.
  func fetchCloudState() async throws -> CompanionSnapshot? {
    let session = try await requireSession()
    let data = try await request(
      path: "/functions/v1/companion-state",
      method: "GET",
      token: session.accessToken
    )
    struct Envelope: Codable {
      var ok: Bool?
      var companion: RemoteCompanion?
    }
    if let env = try? JSONDecoder().decode(Envelope.self, from: data), let row = env.companion {
      return snapshot(from: row)
    }
    return try await fetchMyCompanion()
  }

  func ingestSteps(_ steps: Int, dayKey: String? = nil) async throws -> (energyDelta: Int, energy: Int) {
    let session = try await requireSession()
    var body: [String: Any] = ["steps": steps]
    if let dayKey { body["dayKey"] = dayKey }
    let data = try await request(
      path: "/functions/v1/steps-ingest",
      method: "POST",
      body: body,
      token: session.accessToken
    )
    struct Resp: Codable {
      var energyDelta: Int?
      var energy: Int?
    }
    let resp = try JSONDecoder().decode(Resp.self, from: data)
    return (resp.energyDelta ?? 0, resp.energy ?? 0)
  }

  /// Cria o companion após o quiz, persistindo `traits` (JSONB) + `userId` da sessão (Keychain).
  func createCompanionFromQuiz(
    name: String,
    draft: CompanionQuiz.Draft,
    traits: CompanionQuiz.Traits
  ) async throws -> CompanionSnapshot {
    // Garante sessão (refresh ou anônimo) antes do POST.
    guard let session = await ensurePersistentSession() else {
      throw SupabaseError.noSession
    }
    let userId = KeychainStore.get(.supabaseUserId) ?? session.userId
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    let now = iso.string(from: Date())
    let traitsPayload = traits.asDictionary

    // Novo nascimento: não reaproveita row antiga (evita “mesmo dino” após apagar conta / refazer quiz).
    if let existing = try await fetchMyCompanion() {
      _ = try await request(
        path: "/rest/v1/Companion",
        method: "DELETE",
        query: "id=eq.\(existing.id)",
        token: session.accessToken,
        prefer: "return=minimal"
      )
    }

    let id = "cmp_\(UUID().uuidString.prefix(12))"
    let body: [String: Any] = [
      "id": id,
      "userId": userId,
      "name": name,
      "personality": draft.personality,
      "skin": draft.skin,
      "artStyle": "pixel",
      "backdrop": "sky",
      "archetype": draft.archetype.rawValue,
      "mood": "HAPPY",
      "energy": 80,
      "affection": 55,
      "lastDecayAt": now,
      "lastInteractionAt": now,
      "memoryNotes": [] as [String],
      "traits": traitsPayload,
      "growthStage": "baby",
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
    return CompanionSnapshot(
      id: id,
      name: name,
      mood: "HAPPY",
      moodText: draft.blurb,
      energy: 80,
      affection: 55,
      skin: draft.skin,
      archetype: draft.archetype.rawValue,
      updatedAt: Date(),
      growthStage: "baby",
      createdAt: Date(),
      presenceStatus: "present",
      decayFrozen: false
    )
  }

  func upsertCompanion(_ snap: CompanionSnapshot, personality: String? = nil, traits: [String: Any]? = nil) async throws -> CompanionSnapshot {
    let session = try await requireSession()
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    let now = iso.string(from: Date())

    if let existing = try await fetchMyCompanion() {
      // Metadata only — survival columns protected by trigger on server.
      var body: [String: Any] = [
        "name": snap.name,
        "skin": snap.skin,
        "archetype": snap.archetype,
        "personality": personality ?? snap.archetype,
      ]
      if let traits { body["traits"] = traits }
      _ = try await request(
        path: "/rest/v1/Companion",
        method: "PATCH",
        body: body,
        query: "id=eq.\(existing.id)",
        token: session.accessToken,
        prefer: "return=minimal"
      )
      return try await fetchMyCompanion() ?? existing
    }

    let id = snap.id == "demo" ? "cmp_\(UUID().uuidString.prefix(12))" : snap.id
    var body: [String: Any] = [
      "id": id,
      "userId": KeychainStore.get(.supabaseUserId) ?? session.userId,
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
    if let traits { body["traits"] = traits }
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

  /// Thin client: não envia energy/affection (cloud é autoritativa).
  func pushCompanionState(_ snap: CompanionSnapshot) async throws {
    let session = try await requireSession()
    let body: [String: Any] = [
      "name": snap.name,
      "skin": snap.skin,
      "archetype": snap.archetype,
      "personality": snap.archetype,
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

  func claimMissionCloud(missionId: String) async throws -> (energy: Int, affection: Int, rewardEnergy: Int) {
    let session = try await requireSession()
    let data = try await request(
      path: "/rest/v1/rpc/missions_claim",
      method: "POST",
      body: ["p_mission_id": missionId, "p_user_id": session.userId],
      token: session.accessToken
    )
    struct Claim: Codable {
      var energy: Int?
      var affection: Int?
      var rewardEnergy: Int?
    }
    let claim = try JSONDecoder().decode(Claim.self, from: data)
    return (claim.energy ?? 0, claim.affection ?? 0, claim.rewardEnergy ?? 0)
  }

  func applyInteractionCloud(companionId: String, type: String, message: String? = nil) async throws -> CompanionSnapshot {
    let session = try await requireSession()
    var body: [String: Any] = [
      "p_companion_id": companionId,
      "p_type": type.uppercased(),
      "p_reaction": "…",
    ]
    if let message { body["p_message"] = message }
    let data = try await request(
      path: "/rest/v1/rpc/companion_apply_interaction",
      method: "POST",
      body: body,
      token: session.accessToken
    )
    if let row = try? JSONDecoder().decode(RemoteCompanion.self, from: data) {
      return snapshot(from: row)
    }
    // PostgREST may return array
    if let rows = try? JSONDecoder().decode([RemoteCompanion].self, from: data), let row = rows.first {
      return snapshot(from: row)
    }
    if let cloud = try await fetchCloudState() {
      return cloud
    }
    if let mine = try await fetchMyCompanion() {
      return mine
    }
    return .demo
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
      growthStage: row.growthStage ?? "baby",
      createdAt: nil,
      presenceStatus: row.presenceStatus,
      decayFrozen: row.decayFrozen
    )
  }
}
