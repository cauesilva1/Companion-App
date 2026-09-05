import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class CompanionViewModel: ObservableObject {
  @Published var snapshot: CompanionSnapshot = .demo
  @Published var reaction: String = "Oi! Vamos brincar?"
  @Published var status: String = "local"
  @Published var isBusy = false
  @Published var chatText = ""
  @Published var spriteClip: DinoClip = .idle
  @Published var animNonce: Int = 0
  @Published var followUpQueue: [DinoClip] = []

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
  @Published var needsQuiz: Bool = !CompanionQuiz.isCompleted
  @Published var showAccountPrompt = false
  @Published var isLoggedIn: Bool = false
  @Published var accountEmail: String = ""
  @Published var missions: [LocalMission] = MissionCatalog.ensureToday()

  let pranks = PrankController()
  private var ambientTask: Task<Void, Never>?

  var usesCloud: Bool {
    isLoggedIn && SupabaseConfig.isConfigured && !useLanAPI
  }

  func bootstrap() async {
    if let session = await SupabaseClient.shared.loadSession() {
      isLoggedIn = true
      accountEmail = session.email
    }
    missions = MissionCatalog.ensureToday()
    _ = MissionCatalog.bump(kind: "OPEN_APP")
    NowPlayingService.shared.setEnabled(nowPlayingEnabled)
    if CompanionQuiz.isCompleted {
      apply(snapshot: CompanionSnapshotStore.load() ?? .demo, reaction: nil)
      await refresh()
      await reloadMissions()
      await SyncQueue.flush()
      startAmbientLife()
      if pranksEnabled { pranks.startAmbient() }
      if !isLoggedIn && SupabaseConfig.isConfigured {
        showAccountPrompt = true
      }
    } else {
      needsQuiz = true
    }
  }

  func finishQuiz(draft: CompanionQuiz.Draft, name: String) async {
    let snap = await CompanionEngine.shared.birthFromQuiz(draft: draft, name: name)
    apply(snapshot: snap, reaction: draft.blurb)
    needsQuiz = false
    status = usesCloud ? "supabase" : "standalone"
    playSprite(.eggMove, queue: [.crack, .hatch, .idle])
    if usesCloud {
      await syncBirthToCloud(snap)
    } else if SupabaseConfig.isConfigured {
      showAccountPrompt = true
    }
    await reloadMissions()
    startAmbientLife()
    if pranksEnabled { pranks.startAmbient() }
  }

  func login(email: String, password: String) async throws {
    let session = try await SupabaseClient.shared.signIn(email: email, password: password)
    isLoggedIn = true
    accountEmail = session.email
    status = "supabase"
    showAccountPrompt = false
    if CompanionQuiz.isCompleted {
      await syncBirthToCloud(snapshot)
    }
    await refresh()
    await reloadMissions()
    await SyncQueue.flush()
  }

  func register(email: String, password: String) async throws {
    let session = try await SupabaseClient.shared.signUp(email: email, password: password)
    isLoggedIn = true
    accountEmail = session.email
    status = "supabase"
    showAccountPrompt = false
    if CompanionQuiz.isCompleted {
      await syncBirthToCloud(snapshot)
    }
    await refresh()
    await reloadMissions()
  }

  func logout() {
    Task { await SupabaseClient.shared.signOut() }
    isLoggedIn = false
    accountEmail = ""
    status = "standalone"
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
    spriteClip = .idle
    followUpQueue = []
  }

  func playSprite(_ clip: DinoClip, queue: [DinoClip] = []) {
    spriteClip = clip
    followUpQueue = queue
    animNonce &+= 1
  }

  func refresh() async {
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
        apply(snapshot: snap, reaction: "Oi! Vamos brincar?")
      } catch {
        status = "offline"
        reaction = error.localizedDescription
      }
      return
    }

    if usesCloud {
      do {
        await SyncQueue.flush()
        if let remote = try await SupabaseClient.shared.fetchMyCompanion() {
          companionIdInput = remote.id
          status = "supabase"
          apply(snapshot: remote, reaction: reaction)
          return
        }
        status = "supabase · sem pet"
        await syncBirthToCloud(snapshot)
        return
      } catch {
        status = "supabase offline"
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

    #if canImport(UIKit)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    #endif

    switch interaction {
    case .POKE:
      playSprite(.hurt)
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
        let message = type == "CHAT" ? chatText : nil
        let (snap, line) = try await CompanionAPI.shared.interact(id: id, type: type, message: message)
        if type == "CHAT" { chatText = "" }
        apply(snapshot: snap, reaction: interaction == .PLAY ? reaction : (line ?? "…"))
        await reloadMissions()
      } catch {
        reaction = error.localizedDescription
      }
      return
    }

    var message = type == "CHAT" ? chatText : (type == "TEASE" ? "conta uma piada" : nil)
    if type == "CHAT", let track = NowPlayingService.shared.line {
      let hint = LocalVoice.musicLine(
        title: NowPlayingService.shared.title ?? track,
        artist: NowPlayingService.shared.artist,
        archetype: snapshot.archetype
      )
      let base = message ?? ""
      message = base.isEmpty ? hint : "\(base) (ouvindo: \(track))"
    }

    let (snap, line) = await CompanionEngine.shared.interact(type: interaction, message: message)
    if type == "CHAT" { chatText = "" }
    if let kind = MissionCatalog.kindFromInteraction(type) {
      missions = MissionCatalog.bump(kind: kind)
    }
    if interaction == .PLAY {
      apply(snapshot: snap, reaction: reaction)
    } else {
      apply(snapshot: snap, reaction: line)
    }
    status = usesCloud ? "supabase" : "standalone"
    await pushCloudAfterLocal(snap)
  }

  func reloadMissions() async {
    let local = MissionCatalog.ensureToday()
    if usesCloud {
      do {
        missions = try await SupabaseClient.shared.syncMissions(local, dayKey: MissionCatalog.dayKey())
        return
      } catch {
        SyncQueue.enqueueMissions(local, dayKey: MissionCatalog.dayKey())
      }
    }
    missions = local
  }

  func claimMission(_ mission: LocalMission) async {
    guard mission.complete, !mission.claimed else { return }
    if let result = MissionCatalog.claim(mission.id) {
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
    let track = NowPlayingService.shared.line
    let line = [reaction, track].compactMap { $0 }.joined(separator: " · ")
    do {
      _ = try LiveActivityController.start(snapshot: snapshot, line: line)
    } catch {
      print("[island] \(error.localizedDescription)")
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
        if self.spriteClip != .idle { continue }
        if self.pranks.hidden { continue }
        let clip: DinoClip = Bool.random() ? .move : .dash
        self.playSprite(clip)
      }
    }
  }

  private func syncBirthToCloud(_ snap: CompanionSnapshot) async {
    do {
      let created = try await SupabaseClient.shared.upsertCompanion(snap)
      companionIdInput = created.id
      apply(snapshot: created, reaction: "Pet no Supabase ✓")
      status = "supabase"
      await reloadMissions()
    } catch {
      SyncQueue.enqueuePushState(snap)
      reaction = "Local ok; sync: \(error.localizedDescription)"
    }
  }

  private func pushCloudAfterLocal(_ snap: CompanionSnapshot) async {
    guard usesCloud else { return }
    do {
      try await SupabaseClient.shared.pushCompanionState(snap)
      _ = try await SupabaseClient.shared.syncMissions(missions, dayKey: MissionCatalog.dayKey())
    } catch {
      SyncQueue.enqueuePushState(snap)
      SyncQueue.enqueueMissions(missions, dayKey: MissionCatalog.dayKey())
    }
  }

  private func resolveLanId() async throws -> String {
    saveCompanionId()
    let typed = companionIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
    if !typed.isEmpty { return typed }
    return try await CompanionAPI.shared.resolveCompanionId()
  }

  private func apply(snapshot: CompanionSnapshot, reaction: String?) {
    self.snapshot = snapshot
    if let reaction { self.reaction = reaction }
    CompanionSnapshotStore.save(snapshot)
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

  var body: some View {
    NavigationStack {
      ZStack {
        SkyBackground()
        ScrollView(showsIndicators: false) {
          VStack(spacing: 16) {
            petHero
            if let track = nowPlaying.line {
              musicCard(track)
            }
            statsCard
            speechCard
            missionsCard
            actions
            chatBar
          }
          .padding(.horizontal, 18)
          .padding(.top, 12)
          .padding(.bottom, 28)
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
      }
      .toolbarBackground(.hidden, for: .navigationBar)
      .navigationDestination(isPresented: $showSettings) {
        SettingsView(model: model)
      }
      .fullScreenCover(isPresented: $model.needsQuiz) {
        QuizView { draft, name in
          Task { await model.finishQuiz(draft: draft, name: name) }
        }
      }
      .sheet(isPresented: $model.showAccountPrompt) {
        NavigationStack {
          LoginView(model: model)
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                Button("Agora não") { model.showAccountPrompt = false }
              }
            }
        }
      }
      .task { await model.bootstrap() }
      .onChange(of: scenePhase) { phase in
        if phase == .background, !model.needsQuiz {
          model.startIslandOnLeave()
        }
        if phase == .active {
          NowPlayingService.shared.refresh()
          Task { await SyncQueue.flush() }
        }
      }
    }
  }

  private var petHero: some View {
    VStack(spacing: 12) {
      DinoSpriteView(
        skin: model.snapshot.skin,
        clip: model.spriteClip,
        mood: model.snapshot.mood,
        size: 168,
        animNonce: model.animNonce,
        followUpQueue: model.followUpQueue,
        onBecameIdle: { model.onSpriteBecameIdle() },
        onClipStarted: { SoundService.playClip($0) }
      )
      .opacity(model.pranks.hidden ? 0.05 : 1)
      .scaleEffect(model.pranks.scale)
      .offset(model.pranks.offset)
      .animation(.spring(response: 0.28, dampingFraction: 0.55), value: model.pranks.scale)
      .animation(.easeOut(duration: 0.05), value: model.pranks.offset)

      CompanionCard {
        VStack(spacing: 4) {
          Text(model.snapshot.name)
            .font(.system(size: 32, weight: .bold, design: .rounded))
            .foregroundStyle(CompanionTheme.title)
          Text(LocalVoice.archetypeLabel(model.snapshot.archetype))
            .font(.caption.weight(.semibold))
            .foregroundStyle(CompanionTheme.play)
          Text(moodLine)
            .font(.subheadline)
            .foregroundStyle(CompanionTheme.subtitle)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
      }
    }
  }

  private var moodLine: String {
    let text = model.snapshot.moodText
    if text.lowercased().contains("feliz") { return "Alegre e cheio de energia!" }
    return text
  }

  private func musicCard(_ track: String) -> some View {
    CompanionCard {
      HStack(spacing: 10) {
        Image(systemName: "music.note")
          .foregroundStyle(CompanionTheme.play)
        VStack(alignment: .leading, spacing: 2) {
          Text("Ouvindo")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(CompanionTheme.subtitle)
          Text(track)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CompanionTheme.title)
            .lineLimit(2)
        }
        Spacer(minLength: 0)
      }
    }
  }

  private var statsCard: some View {
    CompanionCard {
      VStack(spacing: 14) {
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
    }
  }

  private var speechCard: some View {
    CompanionCard {
      VStack(alignment: .leading, spacing: 6) {
        Text(model.pranks.line ?? model.reaction)
          .font(.body)
          .foregroundStyle(CompanionTheme.title)
          .fixedSize(horizontal: false, vertical: true)
        Text(Date(), style: .time)
          .font(.caption2)
          .foregroundStyle(CompanionTheme.subtitle)
      }
    }
  }

  private var missionsCard: some View {
    CompanionCard {
      VStack(alignment: .leading, spacing: 10) {
        Text("Missões de hoje")
          .font(.headline)
          .foregroundStyle(CompanionTheme.title)
        ForEach(model.missions) { mission in
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(mission.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CompanionTheme.title)
              Spacer()
              Text("\(mission.progress)/\(mission.target)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(CompanionTheme.subtitle)
            }
            Text(mission.description)
              .font(.caption)
              .foregroundStyle(CompanionTheme.subtitle)
            ProgressView(value: Double(mission.progress), total: Double(max(1, mission.target)))
              .tint(CompanionTheme.play)
            if mission.complete && !mission.claimed {
              Button("Resgatar +\(mission.rewardEnergy)⚡ +\(mission.rewardAffection)❤") {
                Task { await model.claimMission(mission) }
              }
              .font(.caption.weight(.bold))
              .buttonStyle(.borderedProminent)
              .tint(CompanionTheme.feed)
            } else if mission.claimed {
              Text("Resgatada")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(CompanionTheme.play)
            }
          }
          .padding(.vertical, 4)
        }
      }
    }
  }

  private var actions: some View {
    CompanionCard {
      VStack(spacing: 10) {
        HStack(spacing: 10) {
          actionButton("Poke", system: "hand.tap.fill", color: CompanionTheme.poke) {
            await model.interact("POKE")
          }
          actionButton("Feed", system: "fork.knife", color: CompanionTheme.feed) {
            await model.interact("FEED")
          }
          actionButton("Play", system: "gamecontroller.fill", color: CompanionTheme.play) {
            await model.interact("PLAY")
          }
        }
        HStack(spacing: 10) {
          actionButton("Piada", system: "face.smiling.fill", color: CompanionTheme.affection) {
            await model.interact("TEASE")
          }
        }
      }
    }
  }

  private func actionButton(_ title: String, system: String, color: Color, action: @escaping () async -> Void) -> some View {
    Button {
      Task { await action() }
    } label: {
      VStack(spacing: 6) {
        Image(systemName: system)
          .font(.title2)
        Text(title)
          .font(.caption2.weight(.bold))
      }
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity)
      .frame(minHeight: 64)
      .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(color))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .disabled(model.isBusy)
    .opacity(model.isBusy ? 0.75 : 1)
  }

  private var chatBar: some View {
    CompanionCard {
      HStack(spacing: 8) {
        TextField("Digite sua mensagem…", text: $model.chatText)
          .foregroundStyle(CompanionTheme.title)
          .padding(12)
          .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .fill(Color(red: 0.94, green: 0.96, blue: 1.0))
          )
        Button {
          Task { await model.interact("CHAT") }
        } label: {
          Text("Enviar")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(CompanionTheme.play))
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy || model.chatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
  }
}

#Preview {
  ContentView()
}
