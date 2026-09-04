import SwiftUI

@MainActor
final class CompanionViewModel: ObservableObject {
  @Published var snapshot: CompanionSnapshot = .demo
  @Published var reaction: String = "Oi! Sobe a API (`npm run dev:api`) e toca em Atualizar."
  @Published var status: String = "…"
  @Published var isBusy = false
  @Published var chatText = ""
  @Published var apiBase: String = APIConfig.baseURL.absoluteString
  @Published var companionIdInput: String = CompanionAppGroup.defaults.string(forKey: CompanionAppGroup.companionIdKey) ?? ""

  func bootstrap() async {
    apply(snapshot: CompanionSnapshotStore.load() ?? .demo, reaction: nil)
    await refresh()
  }

  func saveAPIBase() {
    APIConfig.setBaseURL(apiBase.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  func saveCompanionId() {
    let id = companionIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
    CompanionAppGroup.defaults.set(id, forKey: CompanionAppGroup.companionIdKey)
  }

  func refresh() async {
    isBusy = true
    defer { isBusy = false }
    do {
      saveAPIBase()
      let ok = try await CompanionAPI.shared.health()
      status = ok ? "API ok" : "API ?"
      let id = try await resolveId()
      companionIdInput = id
      let snap = try await CompanionAPI.shared.fetchState(id: id)
      apply(snapshot: snap, reaction: "Atualizado.")
    } catch {
      status = "offline"
      reaction = error.localizedDescription
    }
  }

  func interact(_ type: String) async {
    isBusy = true
    defer { isBusy = false }
    do {
      saveAPIBase()
      let id = try await resolveId()
      let message = type == "CHAT" ? chatText : nil
      let (snap, line) = try await CompanionAPI.shared.interact(id: id, type: type, message: message)
      if type == "CHAT" { chatText = "" }
      apply(snapshot: snap, reaction: line)
      await LiveActivityController.update(snapshot: snap, line: line)
    } catch {
      reaction = error.localizedDescription
    }
  }

  func startIsland() {
    do {
      _ = try LiveActivityController.start(snapshot: snapshot, line: reaction)
      reaction = "Live Activity / Dynamic Island ligada."
    } catch {
      reaction = error.localizedDescription
    }
  }

  func endIsland() async {
    await LiveActivityController.endAll()
    reaction = "Live Activity encerrada."
  }

  private func resolveId() async throws -> String {
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
  }
}

struct ContentView: View {
  @StateObject private var model = CompanionViewModel()

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          petCard
          reactionCard
          actions
          chatRow
          islandRow
          settings
        }
        .padding()
      }
      .background(
        LinearGradient(
          colors: [Color(red: 0.45, green: 0.72, blue: 0.95), Color(red: 0.95, green: 0.88, blue: 0.75)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
      )
      .navigationTitle("Companion")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task { await model.refresh() }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .disabled(model.isBusy)
        }
      }
      .task { await model.bootstrap() }
    }
  }

  private var petCard: some View {
    VStack(spacing: 12) {
      Text(model.snapshot.moodEmoji)
        .font(.system(size: 72))
      Text(model.snapshot.name)
        .font(.largeTitle.bold())
      Text(model.snapshot.moodText)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      HStack(spacing: 16) {
        meter(title: "Energia", value: model.snapshot.energyPercent, color: .green)
        meter(title: "Afeto", value: model.snapshot.affectionPercent, color: .pink)
      }
      Text(model.status)
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding()
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
  }

  private func meter(title: String, value: Int, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      ProgressView(value: Double(value), total: 100)
        .tint(color)
      Text("\(value)%").font(.caption.monospaced())
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var reactionCard: some View {
    Text(model.reaction)
      .font(.body)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private var actions: some View {
    HStack(spacing: 10) {
      actionButton("Poke", system: "hand.tap") { await model.interact("POKE") }
      actionButton("Feed", system: "fork.knife") { await model.interact("FEED") }
      actionButton("Play", system: "gamecontroller") { await model.interact("PLAY") }
    }
  }

  private func actionButton(_ title: String, system: String, action: @escaping () async -> Void) -> some View {
    Button {
      Task { await action() }
    } label: {
      Label(title, systemImage: system)
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.borderedProminent)
    .disabled(model.isBusy)
  }

  private var chatRow: some View {
    HStack {
      TextField("Fala com o dino…", text: $model.chatText)
        .textFieldStyle(.roundedBorder)
      Button("Enviar") {
        Task { await model.interact("CHAT") }
      }
      .disabled(model.isBusy || model.chatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
  }

  private var islandRow: some View {
    HStack {
      Button("Dynamic Island") { model.startIsland() }
        .buttonStyle(.bordered)
      Button("Encerrar ilha") {
        Task { await model.endIsland() }
      }
      .buttonStyle(.bordered)
    }
  }

  private var settings: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("API base (device: IP do Mac)").font(.caption).foregroundStyle(.secondary)
      TextField("http://192.168.x.x:3333", text: $model.apiBase)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .textFieldStyle(.roundedBorder)
      Text("Companion ID").font(.caption).foregroundStyle(.secondary)
      TextField("cmp-…", text: $model.companionIdInput)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .textFieldStyle(.roundedBorder)
      Text("Widget e lock screen usam o App Group após Atualizar.")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .padding()
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

#Preview {
  ContentView()
}
