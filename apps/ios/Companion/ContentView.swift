import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class CompanionViewModel: ObservableObject {
  @Published var snapshot: CompanionSnapshot = CompanionSnapshotStore.load() ?? .demo
  @Published var reaction: String = "Oi! Vamos brincar?"
  @Published var status: String = "local"
  @Published var isBusy = false
  @Published var chatText = ""
  @Published var spriteClip: DinoClip = .idle
  @Published var animNonce: Int = 0
  @Published var followUpQueue: [DinoClip] = []
  private var ambientBootstrapped = false
  /// Evita refresh do scenePhase brigar com o bootstrap (flip zezinho ↔ pet real).
  private var isBootstrapping = false
  private var refreshGeneration = 0

  @Published var useLanAPI: Bool = CompanionSnapshotStore.useLanAPI()
  @Published var apiBase: String = CompanionSnapshotStore.savedApiBase() ?? "http://192.168.0.10:3333"
  @Published var companionIdInput: String = CompanionSnapshotStore.savedCompanionId() ?? ""

  @Published var nvidiaKey: String = KeychainStore.get(.nvidia) ?? ""
  @Published var openrouterKey: String = KeychainStore.get(.openrouter) ?? ""

  @Published var soundMuted: Bool = SoundService.isMuted
  @Published var lowEnergyNotifEnabled: Bool = LowEnergyNotifier.isEnabled
  @Published var missYouNotifEnabled: Bool = LonelinessNotifier.isEnabled
  @Published var pranksEnabled: Bool = PrankController.isEnabled
  @Published var nowPlayingEnabled: Bool = NowPlayingService.isEnabled
  @Published var musicNotifEnabled: Bool = NowPlayingService.musicNotificationsEnabled
  /// Sem conta email → Login obrigatório (antes do quiz/home).
  @Published var needsAuth: Bool = SupabaseConfig.isConfigured
  /// Quiz só depois do login, se a conta ainda não tiver Companion.
  @Published var needsQuiz: Bool = false
  @Published var showAccountPrompt = false
  /// Abre LoginView já em modo "Criar conta".
  @Published var preferRegisterOnLogin = false
  @Published var isLoggedIn: Bool = false
  @Published var accountEmail: String = ""
  @Published var missions: [LocalMission] = MissionCatalog.ensureToday()
  @Published var isHatching = false
  @Published var historyTick: Int = 0
  /// Evita o refresh puxar um companion antigo da cloud logo após o quiz.
  private var suppressCloudPullUntil: Date?
  /// Mensagem já enviada ao balão enquanto a LLM responde (input fica limpo).
  @Published var pendingChatUser: String?
  @Published var thoughtFeed: [ThoughtFeedEntry] = ThoughtFeedStore.load()
  @Published var openConversationFromWidget = false

  let pranks = PrankController()
  private var ambientTask: Task<Void, Never>?
  private var thoughtTask: Task<Void, Never>?
  private var lastAutonomousThoughtAt: Date = .distantPast

  /// Conta real (email/senha) — anônimo não conta.
  var hasRealAccount: Bool {
    isLoggedIn && !accountEmail.isEmpty && accountEmail != "convidado"
  }

  var usesCloud: Bool {
    hasRealAccount && SupabaseConfig.isConfigured && !useLanAPI
  }

  var chatHistory: [ChatTurn] {
    _ = historyTick
    let store = CompanionLocalStore.load()
    // Sempre todas as conversas CHAT (app single-user) — evita sumir ao trocar id do pet.
    let items = store.interactions
      .filter { $0.type == .CHAT }
      .sorted { $0.createdAt < $1.createdAt }
      .suffix(50)
    var turns: [ChatTurn] = []
    for item in items {
      if let user = item.userMessage, !user.isEmpty {
        turns.append(ChatTurn(id: item.id + "-u", isUser: true, text: user, createdAt: item.createdAt))
      }
      let reply = item.reactionText.trimmingCharacters(in: .whitespacesAndNewlines)
      if !reply.isEmpty, reply != "…" {
        turns.append(
          ChatTurn(
            id: item.id + "-a",
            isUser: false,
            text: reply,
            createdAt: item.createdAt.addingTimeInterval(0.01)
          )
        )
      }
    }
    if let pending = pendingChatUser, !pending.isEmpty {
      turns.append(ChatTurn(id: "pending-user", isUser: true, text: pending, createdAt: Date()))
    }
    return turns
  }

  func bootstrap() async {
    isBootstrapping = true
    defer { isBootstrapping = false }

    missions = MissionCatalog.ensureToday()
    missions = MissionCatalog.bump(kind: "OPEN_APP")
    HouseZoneStore.ensureSeeded()
    thoughtFeed = ThoughtFeedStore.load()
    NowPlayingService.shared.setEnabled(nowPlayingEnabled)
    _ = await LowEnergyNotifier.requestPermission()
    if nowPlayingEnabled {
      NowPlayingService.shared.refresh()
    }

    guard SupabaseConfig.isConfigured, !useLanAPI else {
      // Sem cloud: fluxo local legado (quiz se nunca fez).
      needsAuth = false
      if CompanionQuiz.isCompleted {
        needsQuiz = false
        if let local = Self.bestLocalSnapshot() {
          apply(snapshot: local, reaction: nil)
        }
        await refresh()
        await reloadMissions()
        startAmbientLife()
        if pranksEnabled { pranks.startAmbient() }
      } else {
        needsQuiz = true
      }
      return
    }

    // Auth-first: sem sessão email → tela de Login (nunca quiz anônimo).
    guard let session = await SupabaseClient.shared.ensurePersistentSession() else {
      isLoggedIn = false
      accountEmail = ""
      needsAuth = true
      needsQuiz = false
      await CompanionEngine.shared.setCloudAuthoritative(false)
      status = "login"
      return
    }

    isLoggedIn = true
    accountEmail = session.email.isEmpty ? "conta" : session.email
    needsAuth = false
    await CompanionEngine.shared.setCloudAuthoritative(true)
    await adoptCloudCompanionOrRequireQuiz()
  }

  /// Pós-login: Companion da conta → Home; senão → Quiz. Nunca sobe pet local órfão.
  func adoptCloudCompanionOrRequireQuiz() async {
    do {
      if let details = try await SupabaseClient.shared.fetchMyCompanionDetails() {
        CompanionQuiz.markCompleted()
        needsQuiz = false
        companionIdInput = details.snapshot.id
        _ = await CompanionEngine.shared.adoptCloudSnapshot(details.snapshot)
        apply(snapshot: details.snapshot, reaction: nil)
        if !details.hasTraits {
          await syncBirthToCloud(details.snapshot, ensureTraits: true)
        }
        await refresh()
        await reloadMissions()
        await SyncQueue.flush()
        await BackgroundTelemetry.runForegroundIngest()
        thoughtFeed = ThoughtFeedStore.load()
        startAmbientLife()
        if pranksEnabled { pranks.startAmbient() }
        CompanionNotifier.scheduleProactive(snapshot: snapshot)
        await HealthKitStepsService.shared.requestAuthorization()
        _ = try? await LiveActivityController.startPersistent(snapshot: snapshot)
        status = "supabase"
        return
      }

      // Conta sem Companion → limpa pet local de outra sessão e abre quiz.
      await CompanionEngine.shared.clearAllLocal()
      CompanionQuiz.resetCompleted()
      ThoughtFeedStore.clear()
      snapshot = .demo
      thoughtFeed = []
      companionIdInput = ""
      needsQuiz = true
      status = "supabase · quiz"
    } catch {
      // Offline com flag local: tenta espelho; senão pede quiz só se nunca houve pet.
      if CompanionQuiz.isCompleted, let local = Self.bestLocalSnapshot() {
        needsQuiz = false
        apply(snapshot: local, reaction: nil)
        status = "supabase offline"
        startAmbientLife()
      } else {
        needsQuiz = true
        status = "supabase offline · quiz"
      }
    }
  }

  /// Recebe o companion já persistido pelo QuizView (cloud POST com `traits`).
  func finishQuiz(created: CompanionSnapshot, draft: CompanionQuiz.Draft) async {
    _ = await CompanionEngine.shared.birthFromQuiz(draft: draft, name: created.name)
    var snap = created
    snap.moodText = draft.blurb
    _ = await CompanionEngine.shared.adoptCloudSnapshot(snap)
    if SupabaseConfig.isConfigured {
      await CompanionEngine.shared.setCloudAuthoritative(true)
    }
    companionIdInput = snap.id
    apply(snapshot: snap, reaction: draft.blurb)
    needsQuiz = false
    needsAuth = false
    status = usesCloud ? "supabase" : "standalone"
    isHatching = true
    suppressCloudPullUntil = Date().addingTimeInterval(45)
    playSprite(.eggMove, queue: [.crack, .hatch, .idle])

    // Só sincroniza metadata se já estamos na conta certa (não cria segundo pet).
    if usesCloud {
      await syncBirthToCloud(snap, ensureTraits: true)
    }

    await reloadMissions()
    _ = try? await LiveActivityController.startPersistent(snapshot: snap)

    Task { [weak self] in
      try? await Task.sleep(nanoseconds: 4_500_000_000)
      await MainActor.run {
        self?.isHatching = false
        self?.startAmbientLife()
        if self?.pranksEnabled == true { self?.pranks.startAmbient() }
      }
    }
  }

  func login(email: String, password: String) async throws {
    let session = try await SupabaseClient.shared.signIn(email: email, password: password)
    isLoggedIn = true
    accountEmail = session.email
    needsAuth = false
    status = "supabase"
    showAccountPrompt = false
    preferRegisterOnLogin = false
    // Cloud manda: nunca faz upload do pet local de outra conta/instalação.
    await adoptCloudCompanionOrRequireQuiz()
  }

  func register(email: String, password: String) async throws {
    let session = try await SupabaseClient.shared.signUp(email: email, password: password)
    isLoggedIn = true
    accountEmail = session.email
    needsAuth = false
    status = "supabase"
    showAccountPrompt = false
    preferRegisterOnLogin = false
    await adoptCloudCompanionOrRequireQuiz()
  }

  func logout() {
    Task {
      // Não apaga Companion na cloud — só encerra sessão neste aparelho.
      await SupabaseClient.shared.signOut()
      await CompanionEngine.shared.clearAllLocal()
      CompanionQuiz.resetCompleted()
      ThoughtFeedStore.clear()
      await MainActor.run {
        snapshot = .demo
        thoughtFeed = []
        companionIdInput = ""
        needsQuiz = false
        needsAuth = SupabaseConfig.isConfigured
        reaction = "Saiu da conta. Entre de novo para ver seu companion."
        status = "login"
        isLoggedIn = false
        accountEmail = ""
      }
      await CompanionEngine.shared.setCloudAuthoritative(false)
    }
  }

  func setSoundMuted(_ muted: Bool) {
    soundMuted = muted
    SoundService.isMuted = muted
  }

  func setLowEnergyNotif(_ enabled: Bool) async {
    lowEnergyNotifEnabled = enabled
    LowEnergyNotifier.isEnabled = enabled
    if enabled {
      _ = await LowEnergyNotifier.requestPermission()
    }
  }

  func setMissYouNotif(_ enabled: Bool) async {
    missYouNotifEnabled = enabled
    LonelinessNotifier.isEnabled = enabled
    if enabled {
      _ = await LonelinessNotifier.requestPermission()
    }
  }

  func setPranks(_ enabled: Bool) {
    pranksEnabled = enabled
    pranks.setEnabled(enabled)
  }

  func setNowPlaying(_ enabled: Bool) {
    nowPlayingEnabled = enabled
    NowPlayingService.shared.setEnabled(enabled)
    if enabled {
      Task {
        _ = await LowEnergyNotifier.requestPermission()
        NowPlayingService.shared.refresh()
      }
    }
  }

  func setMusicNotif(_ enabled: Bool) {
    musicNotifEnabled = enabled
    NowPlayingService.musicNotificationsEnabled = enabled
    if enabled {
      Task { _ = await LowEnergyNotifier.requestPermission() }
    }
  }

  func connectSpotify() async {
    do {
      try await SpotifyService.shared.connect()
      reaction = "Spotify conectado ✓ — toque uma faixa"
      NowPlayingService.shared.refresh()
    } catch {
      reaction = error.localizedDescription
    }
  }

  func saveKeys() {
    KeychainStore.set(.nvidia, value: nvidiaKey)
    KeychainStore.set(.openrouter, value: openrouterKey)
    reaction = KeychainStore.hasAnyLLMKey
      ? "Chaves salvas neste iPhone."
      : "Chaves limpas — frases locais."
  }

  func saveAPIBase() {
    APIConfig.setBaseURL(apiBase.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  func saveCompanionId() {
    let id = companionIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
    CompanionSnapshotStore.saveCompanionId(id)
  }

  func setLanMode(_ enabled: Bool) {
    useLanAPI = enabled
    CompanionSnapshotStore.setUseLanAPI(enabled)
  }

  func pasteCompanionIdFromClipboard() {
    #if canImport(UIKit)
    if let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
       text.hasPrefix("cmp-") || text.hasPrefix("c") {
      companionIdInput = text
      saveCompanionId()
      reaction = "ID colado."
    } else {
      reaction = "Clipboard sem ID."
    }
    #endif
  }

  func onSpriteBecameIdle() {
    if spriteClip == .sleep {
      followUpQueue = []
      return
    }
    spriteClip = .idle
    followUpQueue = []
    if isHatching {
      isHatching = false
    }
  }

  func playSprite(_ clip: DinoClip, queue: [DinoClip] = []) {
    spriteClip = clip
    followUpQueue = queue
    animNonce &+= 1
  }

  func refresh() async {
    if isBootstrapping { return }
    // Não marca isBusy — isso acende "digitando…" e compete com o chat ativo.
    if isBusy { return }
    refreshGeneration &+= 1
    let gen = refreshGeneration

    if useLanAPI {
      do {
        saveAPIBase()
        saveCompanionId()
        let ok = try await CompanionAPI.shared.health()
        status = ok ? "API Mac ok" : "API ?"
        let id = try await resolveLanId()
        companionIdInput = id
        let snap = try await CompanionAPI.shared.fetchState(id: id)
        guard gen == refreshGeneration else { return }
        apply(snapshot: snap, reaction: "Oi! Vamos brincar?")
      } catch {
        status = "offline"
        reaction = error.localizedDescription
      }
      return
    }

    if usesCloud {
      do {
        // Logo após o quiz, não deixa a cloud antiga sobrescrever o dino novo.
        if let until = suppressCloudPullUntil, Date() < until {
          status = "supabase · hatch"
          return
        }
        await SyncQueue.flush()
        guard gen == refreshGeneration else { return }
        await CompanionEngine.shared.setCloudAuthoritative(true)
        let remote: CompanionSnapshot?
        if let cloud = try await SupabaseClient.shared.fetchCloudState() {
          remote = cloud.snapshot
        } else {
          remote = try await SupabaseClient.shared.fetchMyCompanion()
        }
        guard gen == refreshGeneration else { return }
        if let remote, !remote.isDemoPlaceholder {
          companionIdInput = remote.id
          status = "supabase"
          _ = await CompanionEngine.shared.adoptCloudSnapshot(remote)
          apply(snapshot: remote, reaction: reaction)
          thoughtFeed = ThoughtFeedStore.load()
          syncThoughtsFromStores()
          if let mode = remote.lifeMode {
            HouseZoneStore.syncWithLifeMode(CompanionLifeMode.parse(mode))
          }
          await LiveActivityController.update(snapshot: remote)
          await ContextTelemetryService.shared.ingestNow()
          // Re-pull leve se o ingest mudou lifeMode / morningThought / thoughts
          if let again = try? await SupabaseClient.shared.fetchCloudState(), !again.snapshot.isDemoPlaceholder {
            apply(snapshot: again.snapshot, reaction: reaction)
            thoughtFeed = ThoughtFeedStore.load()
            syncThoughtsFromStores()
            if let mode = again.snapshot.lifeMode {
              HouseZoneStore.syncWithLifeMode(CompanionLifeMode.parse(mode))
            }
          }
          await consumeMorningThoughtIfNeeded()
          return
        }
        status = "supabase · sem pet"
        // Não sobe pet local órfão — quiz cria o vínculo certo.
        if !needsQuiz {
          CompanionQuiz.resetCompleted()
          needsQuiz = true
        }
        return
      } catch {
        if case SupabaseError.sessionExpired = error {
          isLoggedIn = false
          accountEmail = ""
          needsAuth = true
          needsQuiz = false
          status = "login"
        } else if case SupabaseError.noSession = error {
          isLoggedIn = false
          accountEmail = ""
          needsAuth = true
          needsQuiz = false
          status = "login"
        } else {
          status = "supabase offline"
        }
        reaction = error.localizedDescription
      }
    }

    let snap = await CompanionEngine.shared.currentSnapshot()
    companionIdInput = snap.id
    status = isLoggedIn ? "local mirror" : "standalone"
    let greet = LocalVoice.greeting(
      archetype: snap.archetype,
      hour: Calendar.current.component(.hour, from: Date())
    )
    apply(snapshot: snap, reaction: greet ?? reaction)
  }

  func interact(_ type: String) async {
    guard let interaction = InteractionType(rawValue: type) else { return }
    isBusy = true
    defer { isBusy = false }
    pranks.clearLine()

    #if canImport(UIKit)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    #endif

    // CHAT: joga a mensagem no balão na hora e limpa o input.
    let chatMessage: String? = {
      guard type == "CHAT" else { return nil }
      let msg = chatText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !msg.isEmpty else { return nil }
      chatText = ""
      pendingChatUser = msg
      historyTick &+= 1
      return msg
    }()

    switch interaction {
    case .POKE:
      playSprite(.avoid)
      reaction = LocalVoice.reaction(
        name: snapshot.name,
        archetype: snapshot.archetype,
        mood: CompanionMood(rawValue: snapshot.mood) ?? .CONTENT,
        type: .POKE
      )
    case .PLAY:
      let clip = DinoSpriteCatalog.playClips.randomElement() ?? .jump
      playSprite(clip)
      reaction = LocalVoice.playLine(archetype: snapshot.archetype)
    case .FEED:
      playSprite(.bite)
    case .CHAT:
      playSprite(.scan)
    case .TEASE:
      playSprite(.kick)
      Task { await pranks.run(.teaseSound) }
    case .IGNORE_CHECK:
      break
    }

    if useLanAPI {
      do {
        saveAPIBase()
        let id = try await resolveLanId()
        let message = type == "CHAT" ? chatMessage : nil
        let (snap, line) = try await CompanionAPI.shared.interact(id: id, type: type, message: message)
        apply(snapshot: snap, reaction: interaction == .PLAY || interaction == .POKE ? reaction : (line ?? "…"))
        if type == "CHAT" {
          pendingChatUser = nil
          historyTick &+= 1
        }
        await reloadMissions()
      } catch {
        reaction = error.localizedDescription
        if type == "CHAT", let msg = chatMessage {
          chatText = msg
          pendingChatUser = nil
          historyTick &+= 1
        }
      }
      return
    }

    let message = type == "CHAT" ? chatMessage : (type == "TEASE" ? "conta uma piada" : nil)

    if usesCloud {
      var cloudApplied = false
      do {
        let id = companionIdInput.isEmpty ? snapshot.id : companionIdInput
        var cloudSnap = try await SupabaseClient.shared.applyInteractionCloud(
          companionId: id,
          type: type,
          message: message
        )
        cloudApplied = true
        let traits = CompanionQuiz.loadSavedTraitsDictionary()
        let vibe = traits?["vibe"] as? String
        let style = (traits?["communicationStyle"] as? String)
          ?? (traits?["estiloComunicacao"] as? String)
        let personaBits = [vibe, style].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty && $0.lowercased() != cloudSnap.archetype.lowercased() }
        let personality = personaBits.isEmpty
          ? LocalVoice.archetypeLabel(cloudSnap.archetype)
          : personaBits.joined(separator: " · ")
        let priorHistory: [(role: String, content: String)] = chatHistory
          .filter { $0.id != "pending-user" }
          .suffix(12)
          .map { (role: $0.isUser ? "user" : "assistant", content: $0.text) }
        let line = await LLMService.generate(
          params: .init(
            name: cloudSnap.name,
            personality: personality,
            archetype: cloudSnap.archetype,
            mood: CompanionMood(rawValue: cloudSnap.mood.uppercased()) ?? .CONTENT,
            energy: cloudSnap.energy,
            affection: cloudSnap.affection,
            userMessage: message,
            history: priorHistory,
            memoryNotes: [],
            weatherHint: nil,
            musicHint: NowPlayingService.shared.line,
            growthStage: Growth.effective(cloudSnap.growthStage).rawValue,
            lifeMode: cloudSnap.lifeMode ?? snapshot.lifeMode,
            gamingStatus: cloudSnap.gamingStatus
          ),
          companionId: cloudSnap.id,
          type: interaction
        )
        cloudSnap.moodText = line
        _ = await CompanionEngine.shared.adoptCloudSnapshot(cloudSnap)
        // Cloud atualiza stats; histórico da tela Conversar fica no store local.
        await CompanionEngine.shared.recordInteraction(
          companionId: cloudSnap.id,
          type: interaction,
          userMessage: message,
          reactionText: line,
          energyAfter: cloudSnap.energy,
          affectionAfter: cloudSnap.affection,
          moodAfter: CompanionMood(rawValue: cloudSnap.mood.uppercased()) ?? .CONTENT
        )
        if type == "CHAT" {
          pendingChatUser = nil
          historyTick &+= 1
        }
        if let kind = MissionCatalog.kindFromInteraction(type) {
          missions = MissionCatalog.bump(kind: kind)
        }
        apply(snapshot: cloudSnap, reaction: interaction == .PLAY || interaction == .POKE ? reaction : line)
        status = "supabase"
        await LiveActivityController.update(snapshot: cloudSnap)
        await reloadMissions()
        return
      } catch {
        reaction = error.localizedDescription
        if cloudApplied {
          // Stats já foram aplicados na cloud — só garante o histórico local.
          let fallback = reaction.isEmpty ? "…" : reaction
          await CompanionEngine.shared.recordInteraction(
            companionId: snapshot.id,
            type: interaction,
            userMessage: message,
            reactionText: fallback,
            energyAfter: snapshot.energy,
            affectionAfter: snapshot.affection,
            moodAfter: CompanionMood(rawValue: snapshot.mood.uppercased()) ?? .CONTENT
          )
          if type == "CHAT" {
            pendingChatUser = nil
            historyTick &+= 1
          }
          return
        }
        if type == "CHAT", let msg = chatMessage {
          pendingChatUser = msg
        }
      }
    }

    let (snap, line) = await CompanionEngine.shared.interact(type: interaction, message: message)
    if type == "CHAT" {
      pendingChatUser = nil
      historyTick &+= 1
    }
    if let kind = MissionCatalog.kindFromInteraction(type) {
      missions = MissionCatalog.bump(kind: kind)
    } else {
      missions = MissionCatalog.ensureToday()
    }
    if interaction == .PLAY || interaction == .POKE {
      apply(snapshot: snap, reaction: reaction)
    } else {
      apply(snapshot: snap, reaction: line)
    }
    status = usesCloud ? "supabase" : "standalone"
    await pushCloudAfterLocal(snap)
    missions = MissionCatalog.ensureToday()
  }

  func reloadMissions() async {
    let local = MissionCatalog.ensureToday()
    if usesCloud {
      do {
        let synced = try await SupabaseClient.shared.syncMissions(local, dayKey: MissionCatalog.dayKey())
        MissionCatalog.replaceToday(synced)
        missions = synced
        return
      } catch {
        SyncQueue.enqueueMissions(local, dayKey: MissionCatalog.dayKey())
      }
    }
    missions = local
  }

  func claimMission(_ mission: LocalMission) async {
    guard mission.complete, !mission.claimed else { return }
    if usesCloud {
      do {
        let result = try await SupabaseClient.shared.claimMissionCloud(missionId: mission.id)
        if let cloud = try await SupabaseClient.shared.fetchCloudState() {
          _ = await CompanionEngine.shared.adoptCloudSnapshot(cloud.snapshot)
          apply(snapshot: cloud.snapshot, reaction: "Missão concluída! +\(result.rewardEnergy) energia")
        }
        await reloadMissions()
        return
      } catch {
        reaction = error.localizedDescription
      }
    }
    if let result = MissionCatalog.claim(mission.id) ?? MissionCatalog.claim(mission.kind) {
      missions = result.missions
      var snap = snapshot
      snap.energy = min(100, snap.energy + Double(result.rewardEnergy))
      snap.affection = min(100, snap.affection + Double(result.rewardAffection))
      apply(snapshot: snap, reaction: "Missão concluída! +\(result.rewardEnergy) energia")
      await pushCloudAfterLocal(snap)
      await reloadMissions()
    }
  }

  func startIslandOnLeave() {
    let snap = snapshot
    Task {
      do {
        _ = try await LiveActivityController.startPersistent(snapshot: snap)
      } catch {
        print("[island] \(error.localizedDescription)")
      }
    }
  }

  func startAmbientLife() {
    ambientTask?.cancel()
    ambientTask = Task { [weak self] in
      while !Task.isCancelled {
        let excited = self?.snapshot.mood.uppercased() == "EXCITED"
        let sleepy = self?.snapshot.mood.uppercased() == "SLEEPY"
        let delay = UInt64(((excited ? 6.0 : 9.0) + Double.random(in: 0...(excited ? 4 : 6))) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: delay)
        guard !Task.isCancelled, let self else { return }
        if sleepy { continue }
        if self.needsQuiz { continue }
        if self.isHatching { continue }
        if self.spriteClip != .idle { continue }
        if self.pranks.hidden { continue }
        let clip: DinoClip = Bool.random() ? .move : .dash
        self.playSprite(clip)
      }
    }
    startThoughtFeed()
  }

  func startThoughtFeed() {
    thoughtTask?.cancel()
    thoughtTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      await ContextTelemetryService.shared.ingestNow()
      await self?.consumeMorningThoughtIfNeeded()
      // Primeiro pensamento só após cooldown do modo (não spamma no boot).
      while !Task.isCancelled {
        guard let self else { return }
        let mode = CompanionLifeMode.parse(self.snapshot.lifeMode)
        let delaySec = mode.thoughtCooldownSec + Double.random(in: 0...60)
        try? await Task.sleep(nanoseconds: UInt64(delaySec * 1_000_000_000))
        guard !Task.isCancelled else { return }
        if self.needsQuiz || self.needsAuth || self.isHatching { continue }
        // Telemetria a cada ~2 ciclos, não a cada mensagem
        if Bool.random() {
          await ContextTelemetryService.shared.ingestNow()
        }
        let kind: String = {
          switch CompanionLifeMode.parse(self.snapshot.lifeMode) {
          case .sleep: return "dream"
          case .work: return "work"
          case .indoor: return "rest"
          }
        }()
        await self.emitAutonomousThought(kind: kind)
      }
    }
  }

  /// Injeta o pensamento matinal guardado na cloud na 1ª abertura do dia (depois das 6h).
  func consumeMorningThoughtIfNeeded() async {
    let mode = CompanionLifeMode.parse(snapshot.lifeMode)
    // Antes das 6h ainda está "meio dormindo" — não joga bom-dia.
    guard !mode.isPreWakeDrowsy else { return }
    guard CompanionLifeMode.localHour >= CompanionLifeMode.wakeHour else { return }

    let line = snapshot.morningThought
      ?? LifeModeStore.pendingMorningThought
    guard let line, !line.isEmpty else { return }
    let already = thoughtFeed.contains { $0.kind == "morning" && $0.text == line }
    if !already {
      let entry = ThoughtFeedEntry.make(
        text: line,
        kind: "morning",
        zoneName: HouseZoneStore.activeZone()?.name
      )
      thoughtFeed = ThoughtFeedStore.append(entry)
      reaction = line
      WidgetSpeechStore.saveIdle(line: line, name: snapshot.name)
      WidgetReloader.reload()
    }
    LifeModeStore.pendingMorningThought = nil
    // Ack na cloud (limpa morningThought após consumir)
    _ = try? await SupabaseClient.shared.ingestContext(
      onHomeWifi: nil,
      ssid: nil,
      stepsToday: HealthKitStepsService.shared.todaySteps,
      stepsRecent: 0,
      isCharging: false,
      localHour: Calendar.current.component(.hour, from: Date()),
      mediaActive: false,
      mediaHint: nil,
      homeWifiSsid: LifeModeStore.homeWifiSsid,
      xboxGamertag: LifeModeStore.xboxGamertag,
      ackMorning: true,
      appForeground: true
    )
  }

  func emitAutonomousThought(kind: String) async {
    let mode = CompanionLifeMode.parse(snapshot.lifeMode ?? LifeModeStore.loadMode().rawValue)
    let elapsed = Date().timeIntervalSince(lastAutonomousThoughtAt)
    guard elapsed >= mode.thoughtCooldownSec * 0.85 else { return }

    let traits = CompanionQuiz.loadSavedTraitsDictionary()
    let zoneName: String? = mode == .indoor
      ? HouseZoneStore.resolveActiveZone()?.name
      : HouseZoneStore.locationLabel(lifeMode: mode)
    let localLine = LocalVoice.autonomousThought(
      name: snapshot.name,
      archetype: snapshot.archetype,
      mood: snapshot.mood,
      energy: snapshot.energyPercent,
      zoneName: zoneName,
      traits: traits,
      lifeMode: mode.rawValue,
      gamingStatus: snapshot.gamingStatus,
      mediaHint: snapshot.mediaHint ?? NowPlayingService.shared.line
    )

    var line = localLine
    if KeychainStore.hasAnyLLMKey {
      let prompt: String
      if mode == .sleep {
        prompt = """
        Manda UMA micro-história onírica (1 frase, termine com pontuação) como amigo geek sonhando.
        Temas ok: games, tech, séries, código, cultura pop — surreal e leve.
        PROIBIDO narrar status (sofá, TV ligada, Xbox offline, energia %, regenerar).
        Sem meta, sem aspas, sem explicar o prompt. PT-BR.
        """
      } else {
        prompt = """
        Manda um comentário curto de amigo geek (1–2 frases, termine com . ! ou ?).
        Puxe assunto: tech, games, filmes, séries, código ou cultura pop — opinião, curiosidade ou pergunta aberta.
        Tom maduro, analítico, bom papo. Ângulo novo, nada genérico.
        PROIBIDO narrar ambiente/status: sofá, TV ligada, Xbox offline/ligado, energia %, regenerar, "tô no sofá".
        Sem meta, sem aspas, sem listar traits. PT-BR.
        """
      }
      let generated = await LLMService.generate(
        params: .init(
          name: snapshot.name,
          personality: snapshot.archetype,
          archetype: snapshot.archetype,
          mood: CompanionMood(rawValue: snapshot.mood.uppercased()) ?? .CONTENT,
          energy: snapshot.energy,
          affection: snapshot.affection,
          userMessage: prompt,
          history: [],
          memoryNotes: [],
          weatherHint: nil,
          musicHint: nil,
          growthStage: Growth.effective(snapshot.growthStage).rawValue,
          lifeMode: mode.rawValue,
          gamingStatus: nil
        ),
        companionId: snapshot.id,
        type: .CHAT
      )
      let trimmed = generated.trimmingCharacters(in: .whitespacesAndNewlines)
      if SpeechFilters.acceptAutonomousThought(trimmed) {
        line = trimmed
      }
      // senão mantém localLine geek
    }

    if !SpeechFilters.acceptAutonomousThought(line) {
      line = localLine
    }

    // Dedup: mesmo texto recente no feed local
    if let last = thoughtFeed.last, last.text == line,
       Date().timeIntervalSince(last.createdAt) < 120 {
      return
    }

    lastAutonomousThoughtAt = Date()
    let entry = ThoughtFeedEntry.make(text: line, kind: kind, zoneName: zoneName)
    if usesCloud {
      if let cloud = try? await SupabaseClient.shared.appendThought(
        text: line,
        kind: kind,
        zoneName: zoneName
      ) {
        thoughtFeed = ThoughtFeedStore.load()
        reaction = cloud.text
      } else {
        thoughtFeed = ThoughtFeedStore.append(entry)
        reaction = line
      }
    } else {
      thoughtFeed = ThoughtFeedStore.append(entry)
      reaction = line
    }
    WidgetSpeechStore.saveIdle(line: reaction, name: snapshot.name)
    WidgetReloader.reload()
    historyTick &+= 1
  }

  private func syncBirthToCloud(_ snap: CompanionSnapshot, ensureTraits: Bool = false) async {
    // Nunca publicar o placeholder "zezinho" / id demo na cloud.
    guard !snap.isDemoPlaceholder else {
      reaction = "Sync ignorado (placeholder local)."
      return
    }
    do {
      let traits: [String: Any]? = ensureTraits
        ? CompanionQuiz.traitsDictionaryForSync(archetype: snap.archetype)
        : CompanionQuiz.loadSavedTraitsDictionary()
      let created = try await SupabaseClient.shared.upsertCompanion(
        snap,
        personality: snap.archetype,
        traits: traits
      )
      companionIdInput = created.id
      apply(snapshot: created, reaction: "Pet no Supabase ✓")
      status = "supabase"
      CompanionQuiz.markCompleted()
      needsQuiz = false
      await reloadMissions()
    } catch {
      SyncQueue.enqueuePushState(snap)
      reaction = "Local ok; sync: \(error.localizedDescription)"
    }
  }

  /// Pet real no aparelho (store / engine) — nunca o demo.
  private static func bestLocalSnapshot() -> CompanionSnapshot? {
    if let stored = CompanionSnapshotStore.load(), !stored.isDemoPlaceholder {
      return stored
    }
    let file = CompanionLocalStore.load()
    if let first = file.companions.first {
      let snap = first.toSnapshot()
      if !snap.isDemoPlaceholder { return snap }
    }
    return nil
  }

  private func pushCloudAfterLocal(_ snap: CompanionSnapshot) async {
    guard usesCloud else { return }
    let localMissions = MissionCatalog.ensureToday()
    do {
      try await SupabaseClient.shared.pushCompanionState(snap)
      let synced = try await SupabaseClient.shared.syncMissions(localMissions, dayKey: MissionCatalog.dayKey())
      MissionCatalog.replaceToday(synced)
      missions = synced
    } catch {
      SyncQueue.enqueuePushState(snap)
      SyncQueue.enqueueMissions(localMissions, dayKey: MissionCatalog.dayKey())
    }
  }

  private func resolveLanId() async throws -> String {
    saveCompanionId()
    let typed = companionIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
    if !typed.isEmpty { return typed }
    return try await CompanionAPI.shared.resolveCompanionId()
  }

  private func apply(snapshot: CompanionSnapshot, reaction: String?) {
    // Não deixa o placeholder "zezinho" sobrescrever o pet real (flip vermelho/amarelo).
    if snapshot.isDemoPlaceholder, !self.snapshot.isDemoPlaceholder {
      return
    }

    // Forma visual única (sem growth).
    if ambientBootstrapped {
      if snapshot.mood.uppercased() == "SLEEPY", spriteClip == .idle || spriteClip == .sleep {
        spriteClip = .sleep
      }
    } else {
      ambientBootstrapped = true
      if snapshot.mood.uppercased() == "SLEEPY" {
        spriteClip = .sleep
      }
    }

    self.snapshot = snapshot
    if let reaction {
      pranks.clearLine()
      self.reaction = reaction
      // Só grava no widget se for fala real — status "está feliz" apagava a mensagem.
      if !WidgetSpeechStore.isGenericStatusLine(reaction) {
        WidgetSpeechStore.saveIdle(line: reaction, name: snapshot.name)
      }
    }
    if !snapshot.isDemoPlaceholder {
      CompanionSnapshotStore.save(snapshot)
    }
    WidgetReloader.reload()
    LowEnergyNotifier.check(energyPercent: snapshot.energyPercent, companionName: snapshot.name)
    LonelinessNotifier.check(mood: snapshot.mood, companionName: snapshot.name)
  }

  /// Atualiza mídia / Xbox / lifeMode a partir do snapshot cloud.
  func applyCloudMedia(_ cloud: CompanionSnapshot) {
    var next = snapshot
    next.mediaHint = cloud.mediaHint
    next.gamingStatus = cloud.gamingStatus
    next.lifeMode = cloud.lifeMode ?? next.lifeMode
    next.morningThought = cloud.morningThought
    if let title = cloud.activeTitle { next.activeTitle = title }
    if let tk = cloud.titleKey { next.titleKey = tk }
    if let ek = cloud.equippedTitleKey { next.equippedTitleKey = ek }
    next.energy = cloud.energy
    next.affection = cloud.affection
    next.mood = cloud.mood
    next.presenceStatus = cloud.presenceStatus
    next.decayFrozen = cloud.decayFrozen
    if let mode = next.lifeMode {
      HouseZoneStore.syncWithLifeMode(CompanionLifeMode.parse(mode))
      LifeModeStore.saveMode(CompanionLifeMode.parse(mode))
    }
    apply(snapshot: next, reaction: nil)
  }

  /// Atualiza título equipado vindo do Profile.
  func applyEquippedTitle(activeTitle: String?, titleKey: String?, equippedTitleKey: String?) {
    var next = snapshot
    if let activeTitle { next.activeTitle = activeTitle }
    if let titleKey { next.titleKey = titleKey }
    if let equippedTitleKey { next.equippedTitleKey = equippedTitleKey }
    apply(snapshot: next, reaction: nil)
  }

  /// Garante pensamentos no store — **não** joga greeting/idle genérico no chat.
  func syncThoughtsFromStores() {
    var cleaned = ThoughtFeedStore.load().filter { entry in
      let t = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if t.isEmpty { return false }
      if t == "Oi! Vamos brincar?" { return false }
      if t.localizedCaseInsensitiveContains("crescer") { return false }
      if SpeechFilters.isFalseEvolution(t) { return false }
      return true
    }
    // Remove cópias truncadas ("…") quando a frase completa já existe.
    cleaned = cleaned.filter { entry in
      let t = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard t.hasSuffix("…") || t.hasSuffix("...") else { return true }
      var stem = t
      if stem.hasSuffix("…") { stem = String(stem.dropLast()) }
      if stem.hasSuffix("...") { stem = String(stem.dropLast(3)) }
      stem = stem.trimmingCharacters(in: .whitespacesAndNewlines)
      return !cleaned.contains { other in
        other.id != entry.id && other.text.hasPrefix(stem) && other.text.count > stem.count
      }
    }
    ThoughtFeedStore.save(cleaned)
    thoughtFeed = cleaned
  }

  /// Tap no widget: traz a fala do widget pro fio da home.
  func openFromWidget() {
    syncThoughtsFromStores()
    guard let line = WidgetSpeechStore.displayLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
          !line.isEmpty,
          !WidgetSpeechStore.isGenericStatusLine(line)
    else { return }

    WidgetSpeechStore.saveDisplayLine(line)
    WidgetSpeechStore.saveIdle(line: line, name: snapshot.name)

    if !thoughtFeed.contains(where: { $0.text == line }) {
      let entry = ThoughtFeedEntry.make(
        text: line,
        kind: "mood",
        zoneName: HouseZoneStore.locationLabel(lifeMode: CompanionLifeMode.parse(snapshot.lifeMode))
      )
      thoughtFeed = ThoughtFeedStore.append(entry)
      // Sobe pra cloud pra o próximo sync não sumir com o texto.
      if usesCloud {
        Task {
          _ = try? await SupabaseClient.shared.appendThought(
            text: line,
            kind: "mood",
            zoneName: entry.zoneName
          )
        }
      }
    }
    reaction = line
    historyTick &+= 1
  }
}

struct ContentView: View {
  @StateObject private var model = CompanionViewModel()
  @ObservedObject private var nowPlaying = NowPlayingService.shared
  @Environment(\.scenePhase) private var scenePhase
  @State private var showSettings = false
  @State private var showProfile = false
  @FocusState private var chatFocused: Bool

  /// Conversa + pensamentos **por ordem de tempo** (nunca joga greeting no fim).
  private var homeTurns: [ChatTurn] {
    var turns = model.chatHistory
    let chatTexts = Set(turns.map(\.text))
    let allowedKinds: Set<String> = ["rest", "dream", "work", "music", "morning", "cloud", "mood", "gaming", "widget"]
    for entry in model.thoughtFeed {
      if chatTexts.contains(entry.text) { continue }
      if !allowedKinds.contains(entry.kind) { continue }
      let t = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if t == "Oi! Vamos brincar?" { continue }
      turns.append(
        ChatTurn(id: "feed-\(entry.id)", isUser: false, text: entry.text, createdAt: entry.createdAt)
      )
    }
    return turns.sorted { $0.createdAt < $1.createdAt }
  }

  /// Faixa pra banner: Spotify local, mídia da cloud, ou widget.
  private var musicBannerLine: String? {
    if let line = nowPlaying.line, !line.isEmpty { return line }
    if let hint = model.snapshot.mediaHint?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty {
      return hint
    }
    if let speech = WidgetSpeechStore.load(), speech.hasFreshMusic, let track = speech.trackLine {
      return track
    }
    return nil
  }

  var body: some View {
    NavigationStack {
      ZStack {
        SkyBackground()
        VStack(spacing: 0) {
          compactHero
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 6)
          homeChat
        }
      }
      .preferredColorScheme(.light)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismissChatKeyboard()
            showSettings = true
          } label: {
            Image(systemName: "gearshape.fill")
              .foregroundStyle(CompanionTheme.title)
          }
          .accessibilityLabel("Configuração")
        }
      }
      .toolbarBackground(.hidden, for: .navigationBar)
      .navigationDestination(isPresented: $showSettings) {
        SettingsView(model: model)
      }
      .navigationDestination(isPresented: $showProfile) {
        ProfileView(model: model)
      }
      .fullScreenCover(isPresented: $model.needsAuth) {
        NavigationStack {
          LoginView(model: model, startInRegister: model.preferRegisterOnLogin)
        }
      }
      .fullScreenCover(isPresented: Binding(
        get: { model.needsQuiz && !model.needsAuth },
        set: { model.needsQuiz = $0 }
      )) {
        QuizView { snap, draft in
          Task { await model.finishQuiz(created: snap, draft: draft) }
        }
      }
      .sheet(isPresented: $model.showAccountPrompt) {
        NavigationStack {
          LoginView(model: model, startInRegister: model.preferRegisterOnLogin)
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                Button("Fechar") {
                  model.showAccountPrompt = false
                  model.preferRegisterOnLogin = false
                }
              }
            }
        }
      }
      .task { await model.bootstrap() }
      .onOpenURL { url in
        let host = url.host?.lowercased() ?? ""
        if host == "chat" || host == "feed" || url.path.contains("feed") {
          showSettings = false
          showProfile = false
          dismissChatKeyboard()
          model.openFromWidget()
        }
      }
      .onChange(of: model.openConversationFromWidget) { open in
        if open {
          showSettings = false
          showProfile = false
          dismissChatKeyboard()
          model.openFromWidget()
          model.openConversationFromWidget = false
        }
      }
      .onAppear { dismissChatKeyboard() }
      .onReceive(NotificationCenter.default.publisher(for: .companionNowPlayingChanged)) { note in
        Task {
          await ContextTelemetryService.shared.ingestNow()
          if let cloud = try? await SupabaseClient.shared.fetchCloudState() {
            await MainActor.run {
              model.applyCloudMedia(cloud.snapshot)
              model.thoughtFeed = ThoughtFeedStore.load()
              if let line = note.userInfo?["line"] as? String, !line.isEmpty {
                model.reaction = line
                WidgetSpeechStore.saveIdle(line: line, name: model.snapshot.name)
              }
              WidgetReloader.reload()
            }
          } else {
            await MainActor.run {
              model.thoughtFeed = ThoughtFeedStore.load()
              WidgetReloader.reload()
            }
          }
        }
      }
      .onChange(of: scenePhase) { phase in
        if phase == .active {
          dismissChatKeyboard()
          Task {
            guard !model.needsAuth else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            NowPlayingService.shared.refresh()
            await SyncQueue.flush()
            await model.refresh()
            await BackgroundTelemetry.runForegroundIngest()
            model.syncThoughtsFromStores()
            await model.consumeMorningThoughtIfNeeded()
            _ = try? await LiveActivityController.startPersistent(snapshot: model.snapshot)
          }
          model.missions = MissionCatalog.ensureToday()
          Task { await model.reloadMissions() }
          CompanionNotifier.scheduleProactive(snapshot: model.snapshot)
        }
        if phase == .background, !model.needsQuiz, !model.needsAuth {
          model.startIslandOnLeave()
          CompanionNotifier.scheduleProactive(snapshot: model.snapshot)
          Task {
            await HealthKitStepsService.shared.refreshAndIngest()
            await ContextTelemetryService.shared.ingestNow(appForeground: false)
          }
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
        model.missions = MissionCatalog.ensureToday()
        Task { await model.reloadMissions() }
      }
    }
  }

  private var compactHero: some View {
    HStack(alignment: .center, spacing: 14) {
      ZStack(alignment: .topTrailing) {
        DinoSpriteView(
          skin: model.snapshot.skin,
          clip: model.spriteClip,
          mood: model.snapshot.mood,
          growthStage: Growth.effective(model.snapshot.growthStage).rawValue,
          size: 68,
          animNonce: model.animNonce,
          followUpQueue: model.followUpQueue,
          onBecameIdle: { model.onSpriteBecameIdle() },
          onClipStarted: { SoundService.playClip($0) }
        )
        CompanionContextEmoteOverlay(snapshot: model.snapshot)
      }
      VStack(alignment: .leading, spacing: 8) {
        Text(model.snapshot.name)
          .font(.title3.bold())
          .foregroundStyle(CompanionTheme.title)
        if let title = model.snapshot.activeTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
          Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(CompanionTheme.play)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
              Capsule(style: .continuous)
                .fill(CompanionTheme.play.opacity(0.12))
            )
            .lineLimit(1)
        }
        HStack(spacing: 6) {
          Text(HouseZoneStore.locationLabel(lifeMode: CompanionLifeMode.parse(model.snapshot.lifeMode)))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(CompanionTheme.play)
            .lineLimit(1)
          Text("·")
            .font(.caption2)
            .foregroundStyle(CompanionTheme.subtitle)
          Text(CompanionLifeMode.parse(model.snapshot.lifeMode).labelPT)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(CompanionTheme.subtitle)
            .lineLimit(1)
        }
        StatBar(
          title: "Energia",
          systemImage: "bolt.fill",
          value: model.snapshot.energyPercent,
          color: CompanionTheme.energy
        )
        StatBar(
          title: "Afeto",
          systemImage: "heart.fill",
          value: model.snapshot.affectionPercent,
          color: CompanionTheme.affection
        )
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 14)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Color.white.opacity(0.92))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
    )
    .contentShape(Rectangle())
    .onTapGesture {
      dismissChatKeyboard()
      showProfile = true
    }
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel("Perfil de \(model.snapshot.name)")
  }

  private var homeChat: some View {
    ScrollViewReader { proxy in
      ScrollView(showsIndicators: false) {
        LazyVStack(alignment: .leading, spacing: 12) {
          if let track = musicBannerLine {
            homeMusicBanner(track)
          }
          if homeTurns.isEmpty && !model.isBusy {
            homeEmptyChat
              .id("empty-home-chat")
          }
          ForEach(homeTurns) { turn in
            homeBubble(turn)
              .id(turn.id)
          }
          if model.isBusy {
            homeTyping
              .id("typing")
          }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { dismissChatKeyboard() }
      }
      .scrollDismissesKeyboard(.interactively)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        homeComposer
      }
      .onChange(of: homeTurns.count) { _ in scrollHomeChat(proxy) }
      .onChange(of: model.isBusy) { _ in scrollHomeChat(proxy) }
      .onChange(of: model.historyTick) { _ in scrollHomeChat(proxy) }
      .onAppear { scrollHomeChat(proxy) }
    }
  }

  private var homeComposer: some View {
    VStack(spacing: 0) {
      Divider().overlay(Color.black.opacity(0.08))
      HStack(alignment: .bottom, spacing: 10) {
        TextField("Mensagem…", text: $model.chatText, axis: .vertical)
          .lineLimit(1...4)
          .focused($chatFocused)
          .foregroundStyle(CompanionTheme.title)
          .submitLabel(.send)
          .onSubmit { Task { await sendHomeChat() } }
          .padding(12)
          .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .fill(Color.white)
              .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
          )

        if chatFocused {
          Button {
            dismissChatKeyboard()
          } label: {
            Image(systemName: "keyboard.chevron.compact.down")
              .font(.system(size: 22, weight: .semibold))
              .foregroundStyle(CompanionTheme.subtitle)
              .frame(width: 36, height: 36)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Fechar teclado")
        }

        Button {
          Task { await sendHomeChat() }
        } label: {
          Image(systemName: "arrow.up.circle.fill")
            .font(.system(size: 34))
            .foregroundStyle(canSendHome ? CompanionTheme.play : Color.gray.opacity(0.35))
        }
        .buttonStyle(.plain)
        .disabled(!canSendHome)
        .accessibilityLabel("Enviar")
      }
      .padding(.horizontal, 14)
      .padding(.top, 10)
      .padding(.bottom, 10)
      .background(Color.white.opacity(0.96))
    }
  }

  private var canSendHome: Bool {
    !model.isBusy && !model.chatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func dismissChatKeyboard() {
    chatFocused = false
    #if canImport(UIKit)
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder),
      to: nil,
      from: nil,
      for: nil
    )
    #endif
  }

  private func sendHomeChat() async {
    guard canSendHome else { return }
    dismissChatKeyboard()
    await model.interact("CHAT")
  }

  private func scrollHomeChat(_ proxy: ScrollViewProxy) {
    if model.isBusy {
      withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
    } else if let last = homeTurns.last?.id {
      withAnimation { proxy.scrollTo(last, anchor: .bottom) }
    }
  }

  private var homeEmptyChat: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Fala com \(model.snapshot.name)")
        .font(.subheadline.weight(.bold))
        .foregroundStyle(CompanionTheme.title)
      Text("A conversa fica aqui. Pensamentos autônomos entram no fio por horário — sem bagunçar a ordem.")
        .font(.caption)
        .foregroundStyle(CompanionTheme.subtitle)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color.white.opacity(0.9))
    )
  }

  private var homeTyping: some View {
    HStack(alignment: .top, spacing: 10) {
      DinoStaticFrame(skin: model.snapshot.skin, size: 34)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      Text("\(model.snapshot.name) está digitando…")
        .font(.caption)
        .foregroundStyle(CompanionTheme.subtitle)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.92))
        )
      Spacer(minLength: 24)
    }
  }

  private func homeMusicBanner(_ text: String) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "music.note")
        .foregroundStyle(CompanionTheme.play)
      Text(text)
        .font(.caption.weight(.semibold))
        .foregroundStyle(CompanionTheme.title)
        .lineLimit(2)
      Spacer(minLength: 0)
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.white.opacity(0.88))
    )
  }

  @ViewBuilder
  private func homeBubble(_ turn: ChatTurn) -> some View {
    if turn.isUser {
      HStack {
        Spacer(minLength: 36)
        Text(turn.text)
          .font(.body)
          .foregroundStyle(.white)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .fill(CompanionTheme.play)
          )
      }
    } else {
      HStack(alignment: .top, spacing: 10) {
        DinoStaticFrame(skin: model.snapshot.skin, size: 34)
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        VStack(alignment: .leading, spacing: 4) {
          Text(model.snapshot.name)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(CompanionTheme.subtitle)
          Text(turn.text)
            .font(.body)
            .foregroundStyle(CompanionTheme.title)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
              RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.07), radius: 5, y: 2)
            )
        }
        Spacer(minLength: 28)
      }
    }
  }
}

#Preview {
  ContentView()
}
