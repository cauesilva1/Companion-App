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
  private var lastGrowthStage: GrowthStage = .baby
  private var growthBootstrapped = false
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
  @Published var growthEnabled: Bool = Growth.isEnabled
  @Published var nowPlayingEnabled: Bool = NowPlayingService.isEnabled
  @Published var musicNotifEnabled: Bool = NowPlayingService.musicNotificationsEnabled
  @Published var needsQuiz: Bool = !CompanionQuiz.isCompleted
  @Published var showAccountPrompt = false
  /// Popup pós-quiz: convida a criar conta para não perder o pet só no telefone.
  @Published var showSaveOnlinePrompt = false
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

  var usesCloud: Bool {
    isLoggedIn && SupabaseConfig.isConfigured && !useLanAPI
  }

  var chatHistory: [ChatTurn] {
    _ = historyTick
    let store = CompanionLocalStore.load()
    let forPet = store.interactions.filter { $0.companionId == snapshot.id && $0.type == .CHAT }
    let source = forPet.isEmpty
      ? store.interactions.filter { $0.type == .CHAT }
      : forPet
    let items = source.sorted { $0.createdAt < $1.createdAt }.suffix(40)
    var turns: [ChatTurn] = []
    for item in items {
      if let user = item.userMessage, !user.isEmpty {
        turns.append(ChatTurn(id: item.id + "-u", isUser: true, text: user))
      }
      turns.append(ChatTurn(id: item.id + "-a", isUser: false, text: item.reactionText))
    }
    if let pending = pendingChatUser, !pending.isEmpty {
      turns.append(ChatTurn(id: "pending-user", isUser: true, text: pending))
    }
    return turns
  }

  func bootstrap() async {
    isBootstrapping = true
    defer { isBootstrapping = false }

    // Sessão persistente: refresh automático ou login anônimo (sem pedir email).
    if let session = await SupabaseClient.shared.ensurePersistentSession() {
      isLoggedIn = true
      accountEmail = session.isAnonymous
        ? "convidado"
        : (session.email.isEmpty ? "conta" : session.email)
      await CompanionEngine.shared.setCloudAuthoritative(true)
    } else {
      isLoggedIn = false
      accountEmail = ""
      await CompanionEngine.shared.setCloudAuthoritative(false)
    }
    missions = MissionCatalog.ensureToday()
    missions = MissionCatalog.bump(kind: "OPEN_APP")
    HouseZoneStore.ensureSeeded()
    thoughtFeed = ThoughtFeedStore.load()
    NowPlayingService.shared.setEnabled(nowPlayingEnabled)
    _ = await LowEnergyNotifier.requestPermission()
    if nowPlayingEnabled {
      NowPlayingService.shared.refresh()
    }

    // Preferir pet local real imediatamente (evita flash do demo "zezinho").
    if let local = Self.bestLocalSnapshot(), !local.isDemoPlaceholder {
      apply(snapshot: local, reaction: nil)
    }

    // Cloud-First: se a conta JÁ tem companion, não pede quiz de novo
    // (mesmo sem coluna traits — login antigo / sync sem traits).
    if usesCloud {
      do {
        if let details = try await SupabaseClient.shared.fetchMyCompanionDetails() {
          CompanionQuiz.markCompleted()
          needsQuiz = false
          companionIdInput = details.snapshot.id
          _ = await CompanionEngine.shared.adoptCloudSnapshot(details.snapshot)
          apply(snapshot: details.snapshot, reaction: nil)
          // Backfill traits mínimos se a row antiga não tiver.
          if !details.hasTraits {
            await syncBirthToCloud(details.snapshot, ensureTraits: true)
          }
          await refresh()
          await reloadMissions()
          await SyncQueue.flush()
          startAmbientLife()
          if pranksEnabled { pranks.startAmbient() }
          CompanionNotifier.scheduleProactive(snapshot: snapshot)
          await HealthKitStepsService.shared.requestAuthorization()
          _ = try? await LiveActivityController.startPersistent(snapshot: snapshot)
          return
        }
        // Conta sem pet → quiz (não apaga nada: não há row).
        if !CompanionQuiz.isCompleted {
          needsQuiz = true
          status = "supabase · quiz"
          return
        }
        // Quiz marcado localmente mas cloud vazia → sobe o pet local.
        needsQuiz = false
        if let local = Self.bestLocalSnapshot() {
          apply(snapshot: local, reaction: nil)
          await syncBirthToCloud(local, ensureTraits: true)
        }
        await refresh()
        await reloadMissions()
        startAmbientLife()
        if pranksEnabled { pranks.startAmbient() }
        return
      } catch {
        // Sem rede: se o quiz nunca foi marcado, abre mesmo assim.
        if !CompanionQuiz.isCompleted {
          needsQuiz = true
          status = "supabase offline · quiz"
          return
        }
      }
    }

    if CompanionQuiz.isCompleted {
      needsQuiz = false
      if let local = Self.bestLocalSnapshot() {
        apply(snapshot: local, reaction: nil)
      }
      await refresh()
      await reloadMissions()
      await SyncQueue.flush()
      startAmbientLife()
      if pranksEnabled { pranks.startAmbient() }
      CompanionNotifier.scheduleProactive(snapshot: snapshot)
      await HealthKitStepsService.shared.requestAuthorization()
      _ = try? await LiveActivityController.startPersistent(snapshot: snapshot)
    } else {
      needsQuiz = true
    }
  }

  /// Recebe o companion já persistido pelo QuizView (cloud POST com `traits`, ou local standalone).
  func finishQuiz(created: CompanionSnapshot, draft: CompanionQuiz.Draft) async {
    // Alinha store local (personality/skin) e depois sobrescreve id/stats com a cloud.
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
    status = usesCloud ? "supabase" : "standalone"
    isHatching = true
    suppressCloudPullUntil = Date().addingTimeInterval(45)
    playSprite(.eggMove, queue: [.crack, .hatch, .idle])

    var shouldPromptAccount = SupabaseConfig.isConfigured
    if let session = await SupabaseClient.shared.ensurePersistentSession() {
      isLoggedIn = true
      accountEmail = session.isAnonymous
        ? "convidado"
        : (session.email.isEmpty ? "conta" : session.email)
      shouldPromptAccount = session.isAnonymous || session.email.isEmpty
        || session.email.lowercased().contains("anonymous")
      // Garante que a cloud fica com ESTE dino (não o antigo).
      await syncBirthToCloud(snap, ensureTraits: true)
    } else {
      isLoggedIn = false
      accountEmail = ""
    }

    await reloadMissions()
    _ = try? await LiveActivityController.startPersistent(snapshot: snap)

    if shouldPromptAccount {
      // Depois do hatch começar, mostra o convite para guardar online.
      Task { [weak self] in
        try? await Task.sleep(nanoseconds: 900_000_000)
        await MainActor.run {
          self?.preferRegisterOnLogin = true
          self?.showSaveOnlinePrompt = true
        }
      }
    }

    // Ambient só depois do hatch (evita cortar ovo → crack → hatch).
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
    // Nunca subir o placeholder "zezinho" — só pet real do store/engine.
    let localSnap = Self.bestLocalSnapshot() ?? (snapshot.isDemoPlaceholder ? nil : snapshot)
    let session = try await SupabaseClient.shared.signIn(email: email, password: password)
    isLoggedIn = true
    accountEmail = session.email
    status = "supabase"
    showAccountPrompt = false
    preferRegisterOnLogin = false

    Task { [weak self] in
      guard let self else { return }
      if let localSnap {
        await self.syncBirthToCloud(localSnap, ensureTraits: true)
      }
      await self.refresh()
      await self.reloadMissions()
      await SyncQueue.flush()
    }
  }

  func register(email: String, password: String) async throws {
    let localSnap = Self.bestLocalSnapshot() ?? (snapshot.isDemoPlaceholder ? nil : snapshot)
    let session = try await SupabaseClient.shared.signUp(email: email, password: password)
    isLoggedIn = true
    accountEmail = session.email
    status = "supabase"
    showAccountPrompt = false
    preferRegisterOnLogin = false

    Task { [weak self] in
      guard let self else { return }
      if let localSnap {
        await self.syncBirthToCloud(localSnap, ensureTraits: true)
      }
      await self.refresh()
      await self.reloadMissions()
      await SyncQueue.flush()
    }
  }

  func logout() {
    Task {
      // Apaga pet remoto da sessão atual (convidado/email) e limpa o telefone.
      try? await SupabaseClient.shared.deleteMyCompanions()
      await SupabaseClient.shared.signOut()
      await CompanionEngine.shared.clearAllLocal()
      CompanionQuiz.resetCompleted()
      ThoughtFeedStore.clear()
      await MainActor.run {
        snapshot = .demo
        thoughtFeed = []
        companionIdInput = ""
        needsQuiz = true
        reaction = "Conta encerrada. Faça o quiz de novo."
        status = "logout"
        isLoggedIn = false
        accountEmail = ""
      }
      // Nova sessão anônima limpa (sem carregar pet antigo).
      if let session = await SupabaseClient.shared.ensurePersistentSession() {
        await MainActor.run {
          isLoggedIn = true
          accountEmail = session.isAnonymous ? "convidado" : session.email
          status = "supabase · quiz"
        }
      }
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

  func setGrowthEnabled(_ enabled: Bool) {
    growthEnabled = enabled
    Growth.isEnabled = enabled
    if !enabled {
      lastGrowthStage = .baby
      reaction = "Evolução desligada — só a forma base."
    } else {
      reaction = "Evolução beta ligada. Arte ainda em teste."
    }
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
    refreshGeneration &+= 1
    let gen = refreshGeneration
    isBusy = true
    defer { isBusy = false }

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
          remote = cloud
        } else {
          remote = try await SupabaseClient.shared.fetchMyCompanion()
        }
        guard gen == refreshGeneration else { return }
        if let remote, !remote.isDemoPlaceholder {
          companionIdInput = remote.id
          status = "supabase"
          _ = await CompanionEngine.shared.adoptCloudSnapshot(remote)
          apply(snapshot: remote, reaction: reaction)
          await LiveActivityController.update(snapshot: remote)
          await ContextTelemetryService.shared.ingestNow()
          // Re-pull leve se o ingest mudou lifeMode / morningThought
          if let again = try? await SupabaseClient.shared.fetchCloudState(), !again.isDemoPlaceholder {
            apply(snapshot: again, reaction: reaction)
          }
          await consumeMorningThoughtIfNeeded()
          return
        }
        status = "supabase · sem pet"
        if let local = Self.bestLocalSnapshot() {
          await syncBirthToCloud(local, ensureTraits: true)
        }
        return
      } catch {
        if case SupabaseError.sessionExpired = error {
          if let session = await SupabaseClient.shared.ensurePersistentSession() {
            isLoggedIn = true
            accountEmail = session.isAnonymous ? "convidado" : session.email
            status = "supabase"
          } else {
            isLoggedIn = false
            showAccountPrompt = true
            status = "login"
          }
        } else if case SupabaseError.noSession = error {
          if let session = await SupabaseClient.shared.ensurePersistentSession() {
            isLoggedIn = true
            accountEmail = session.isAnonymous ? "convidado" : session.email
            status = "supabase"
          } else {
            isLoggedIn = false
            showAccountPrompt = true
            status = "login"
          }
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
    defer {
      isBusy = false
      if type == "CHAT" {
        pendingChatUser = nil
        historyTick &+= 1
      }
    }
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
        await reloadMissions()
      } catch {
        reaction = error.localizedDescription
        if type == "CHAT", let msg = chatMessage {
          chatText = msg
        }
      }
      return
    }

    let message = type == "CHAT" ? chatMessage : (type == "TEASE" ? "conta uma piada" : nil)

    if usesCloud {
      do {
        let id = companionIdInput.isEmpty ? snapshot.id : companionIdInput
        var cloudSnap = try await SupabaseClient.shared.applyInteractionCloud(
          companionId: id,
          type: type,
          message: message
        )
        let line = await LLMService.generate(
          params: .init(
            name: cloudSnap.name,
            personality: cloudSnap.archetype,
            archetype: cloudSnap.archetype,
            mood: CompanionMood(rawValue: cloudSnap.mood.uppercased()) ?? .CONTENT,
            energy: cloudSnap.energy,
            affection: cloudSnap.affection,
            userMessage: message,
            history: [],
            memoryNotes: [],
            weatherHint: nil,
            musicHint: NowPlayingService.shared.line,
            growthStage: Growth.effective(cloudSnap.growthStage).rawValue
          ),
          companionId: cloudSnap.id,
          type: interaction
        )
        cloudSnap.moodText = line
        _ = await CompanionEngine.shared.adoptCloudSnapshot(cloudSnap)
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
      }
    }

    let (snap, line) = await CompanionEngine.shared.interact(type: interaction, message: message)
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
    // Garante UI alinhada ao catálogo pós-sync (progress nunca some).
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
          _ = await CompanionEngine.shared.adoptCloudSnapshot(cloud)
          apply(snapshot: cloud, reaction: "Missão concluída! +\(result.rewardEnergy) energia")
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
      try? await Task.sleep(nanoseconds: 800_000_000)
      await ContextTelemetryService.shared.ingestNow()
      await self?.consumeMorningThoughtIfNeeded()
      try? await Task.sleep(nanoseconds: 400_000_000)
      await self?.emitAutonomousThought(kind: "cloud")
      while !Task.isCancelled {
        let mode = CompanionLifeMode.parse(self?.snapshot.lifeMode)
        // Em sleep, não spam de pensamentos — só hiberna.
        let delaySec = mode == .sleep ? 120.0 : (14.0 + Double.random(in: 0...10))
        let delay = UInt64(delaySec * 1_000_000_000)
        try? await Task.sleep(nanoseconds: delay)
        guard !Task.isCancelled, let self else { return }
        if self.needsQuiz || self.isHatching { continue }
        if CompanionLifeMode.parse(self.snapshot.lifeMode) == .sleep { continue }
        await ContextTelemetryService.shared.ingestNow()
        await self.emitAutonomousThought(kind: "mood")
      }
    }
  }

  /// Injeta o pensamento matinal guardado na cloud na 1ª abertura do dia.
  func consumeMorningThoughtIfNeeded() async {
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
      ackMorning: true
    )
  }

  func emitAutonomousThought(kind: String) async {
    let zone = HouseZoneStore.resolveActiveZone()
    let traits = CompanionQuiz.loadSavedTraitsDictionary()
    let mode = CompanionLifeMode.parse(snapshot.lifeMode ?? LifeModeStore.loadMode().rawValue)
    let localLine = LocalVoice.autonomousThought(
      name: snapshot.name,
      archetype: snapshot.archetype,
      mood: snapshot.mood,
      energy: snapshot.energyPercent,
      zoneName: zone?.name,
      traits: traits,
      lifeMode: mode.rawValue,
      gamingStatus: snapshot.gamingStatus,
      mediaHint: snapshot.mediaHint ?? NowPlayingService.shared.line
    )

    var line = localLine
    if KeychainStore.hasAnyLLMKey, mode != .sleep {
      let vibe = (traits?["vibe"] as? String) ?? snapshot.archetype
      let focus = (traits?["focus"] as? String) ?? snapshot.archetype
      let style = (traits?["communicationStyle"] as? String)
        ?? (traits?["estiloComunicacao"] as? String)
        ?? snapshot.archetype
      let zoneHint = zone.map { "Está em \($0.name) (\($0.kind))." } ?? ""
      let gamingHint = (mode == .indoor ? snapshot.gamingStatus : nil).map { "Xbox: \($0)." } ?? ""
      let prompt = """
      Fala curta (1 frase) como pensamento autônomo do companion.
      LifeMode: \(mode.rawValue). \(mode.llmToneHint)
      Traits: vibe=\(vibe), foco=\(focus), comunicação=\(style).
      \(zoneHint) \(gamingHint)
      Sem aspas. PT-BR.
      """
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
          musicHint: mode == .indoor ? NowPlayingService.shared.line : nil,
          growthStage: Growth.effective(snapshot.growthStage).rawValue,
          lifeMode: mode.rawValue,
          gamingStatus: mode == .indoor ? snapshot.gamingStatus : nil
        ),
        companionId: snapshot.id,
        type: .CHAT
      )
      let trimmed = generated.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { line = trimmed }
    }

    let entry = ThoughtFeedEntry.make(text: line, kind: kind, zoneName: zone?.name)
    thoughtFeed = ThoughtFeedStore.append(entry)
    reaction = line
    WidgetSpeechStore.saveIdle(line: line, name: snapshot.name)
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

    // Forma base enquanto growth OFF; com ON usa o stage efetivo do snapshot.
    lastGrowthStage = Growth.effective(snapshot.growthStage)

    if growthBootstrapped {
      if snapshot.mood.uppercased() == "SLEEPY", spriteClip == .idle || spriteClip == .sleep {
        spriteClip = .sleep
      }
    } else {
      growthBootstrapped = true
      if snapshot.mood.uppercased() == "SLEEPY" {
        spriteClip = .sleep
      }
    }

    self.snapshot = snapshot
    if let reaction {
      pranks.clearLine()
      self.reaction = reaction
      WidgetSpeechStore.saveIdle(line: reaction, name: snapshot.name)
    }
    if !snapshot.isDemoPlaceholder {
      CompanionSnapshotStore.save(snapshot)
    }
    WidgetReloader.reload()
    LowEnergyNotifier.check(energyPercent: snapshot.energyPercent, companionName: snapshot.name)
    LonelinessNotifier.check(mood: snapshot.mood, companionName: snapshot.name)
  }
}

struct ContentView: View {
  @StateObject private var model = CompanionViewModel()
  @ObservedObject private var nowPlaying = NowPlayingService.shared
  @Environment(\.scenePhase) private var scenePhase
  @State private var showSettings = false
  @State private var showChat = false

  var body: some View {
    NavigationStack {
      ZStack {
        SkyBackground()
        VStack(spacing: 0) {
          compactHero
            .padding(.horizontal, 18)
            .padding(.top, 8)
          dialogueFeed
        }
      }
      .preferredColorScheme(.light)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            showSettings = true
          } label: {
            Image(systemName: "gearshape.fill")
              .foregroundStyle(CompanionTheme.title)
          }
          .accessibilityLabel("Configuração")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            showChat = true
          } label: {
            Image(systemName: "bubble.left.and.bubble.right.fill")
              .foregroundStyle(CompanionTheme.title)
          }
          .accessibilityLabel("Conversar")
        }
      }
      .toolbarBackground(.hidden, for: .navigationBar)
      .navigationDestination(isPresented: $showSettings) {
        SettingsView(model: model)
      }
      .fullScreenCover(isPresented: $model.needsQuiz) {
        QuizView { snap, draft in
          Task { await model.finishQuiz(created: snap, draft: draft) }
        }
      }
      .alert("Guardar seu companion online?", isPresented: $model.showSaveOnlinePrompt) {
        Button("Criar conta") {
          model.preferRegisterOnLogin = true
          model.showAccountPrompt = true
        }
        Button("Agora não", role: .cancel) {}
      } message: {
        Text(
          "Crie uma conta para guardar \(model.snapshot.name) na nuvem (iPhone e Mac). Sem conta, ele fica só neste telefone."
        )
      }
      .sheet(isPresented: $model.showAccountPrompt) {
        NavigationStack {
          LoginView(model: model, startInRegister: model.preferRegisterOnLogin)
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                Button("Agora não") {
                  model.showAccountPrompt = false
                  model.preferRegisterOnLogin = false
                }
              }
            }
        }
      }
      .sheet(isPresented: $showChat) {
        NavigationStack {
          ChatView(model: model)
        }
      }
      .task { await model.bootstrap() }
      .onOpenURL { url in
        // Widget → feed passivo da home; companion://chat abre conversa ativa.
        let host = url.host?.lowercased() ?? ""
        if host == "chat" {
          showChat = true
        } else if host == "feed" || url.path.contains("feed") {
          showChat = false
          showSettings = false
        }
      }
      .onChange(of: model.openConversationFromWidget) { open in
        if open {
          showChat = false
          showSettings = false
          model.openConversationFromWidget = false
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .companionNowPlayingChanged)) { note in
        if let line = note.userInfo?["line"] as? String, !line.isEmpty {
          model.reaction = line
          WidgetSpeechStore.saveIdle(line: line, name: model.snapshot.name)
          let entry = ThoughtFeedEntry.make(
            text: line,
            kind: "music",
            zoneName: HouseZoneStore.activeZone()?.name
          )
          model.thoughtFeed = ThoughtFeedStore.append(entry)
          WidgetReloader.reload()
        }
      }
      .onChange(of: scenePhase) { phase in
        if phase == .active {
          Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            await SyncQueue.flush()
            await model.refresh()
            await HealthKitStepsService.shared.refreshAndIngest()
            await ContextTelemetryService.shared.ingestNow()
            _ = try? await LiveActivityController.startPersistent(snapshot: model.snapshot)
          }
          model.missions = MissionCatalog.ensureToday()
          Task { await model.reloadMissions() }
          NowPlayingService.shared.refresh()
          CompanionNotifier.scheduleProactive(snapshot: model.snapshot)
        }
        if phase == .background, !model.needsQuiz {
          model.startIslandOnLeave()
          CompanionNotifier.scheduleProactive(snapshot: model.snapshot)
          Task { await HealthKitStepsService.shared.refreshAndIngest() }
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
        model.missions = MissionCatalog.ensureToday()
        Task { await model.reloadMissions() }
      }
    }
  }

  private var compactHero: some View {
    HStack(spacing: 14) {
      DinoSpriteView(
        skin: model.snapshot.skin,
        clip: model.spriteClip,
        mood: model.snapshot.mood,
        growthStage: Growth.effective(model.snapshot.growthStage).rawValue,
        size: 88,
        animNonce: model.animNonce,
        followUpQueue: model.followUpQueue,
        onBecameIdle: { model.onSpriteBecameIdle() },
        onClipStarted: { SoundService.playClip($0) }
      )
      VStack(alignment: .leading, spacing: 8) {
        Text(model.snapshot.name)
          .font(.title2.bold())
          .foregroundStyle(CompanionTheme.title)
        if let zone = HouseZoneStore.activeZone() {
          Text(zone.name)
            .font(.caption.weight(.semibold))
            .foregroundStyle(CompanionTheme.play)
        }
        Text(CompanionLifeMode.parse(model.snapshot.lifeMode).labelPT)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(CompanionTheme.subtitle)
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
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(Color.white.opacity(0.92))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    )
  }

  private var dialogueFeed: some View {
    ScrollViewReader { proxy in
      ScrollView(showsIndicators: false) {
        LazyVStack(alignment: .leading, spacing: 12) {
          if let track = nowPlaying.line {
            feedBanner(icon: "music.note", text: track)
          }
          ForEach(model.thoughtFeed.suffix(40)) { entry in
            feedBubble(entry)
              .id(entry.id)
          }
          if model.thoughtFeed.isEmpty {
            Text("O canal está vivo — \(model.snapshot.name) fala sozinho conforme o estado na nuvem.")
              .font(.subheadline)
              .foregroundStyle(CompanionTheme.subtitle)
              .padding(.top, 24)
              .frame(maxWidth: .infinity)
          }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .padding(.bottom, 28)
      }
      .onChange(of: model.thoughtFeed.count) { _ in
        if let last = model.thoughtFeed.last?.id {
          withAnimation { proxy.scrollTo(last, anchor: .bottom) }
        }
      }
    }
  }

  private func feedBanner(icon: String, text: String) -> some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .foregroundStyle(CompanionTheme.play)
      Text(text)
        .font(.caption.weight(.semibold))
        .foregroundStyle(CompanionTheme.title)
        .lineLimit(2)
      Spacer(minLength: 0)
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color.white.opacity(0.85))
    )
  }

  private func feedBubble(_ entry: ThoughtFeedEntry) -> some View {
    HStack(alignment: .top, spacing: 10) {
      DinoStaticFrame(skin: model.snapshot.skin, size: 36)
      VStack(alignment: .leading, spacing: 4) {
        Text(entry.text)
          .font(.body)
          .foregroundStyle(CompanionTheme.title)
          .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 6) {
          if let zone = entry.zoneName {
            Text(zone)
              .font(.caption2.weight(.semibold))
              .foregroundStyle(CompanionTheme.play)
          }
          Text(entry.createdAt, style: .time)
            .font(.caption2)
            .foregroundStyle(CompanionTheme.subtitle)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color.white.opacity(0.92))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    )
  }
}

#Preview {
  ContentView()
}
