import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class CompanionViewModel: ObservableObject {
  @Published var snapshot: CompanionSnapshot = .demo
  @Published var reaction: String = "Oi! Sobe a API (`npm run dev:api`) e toca em Atualizar."
  @Published var status: String = "…"
  @Published var storageHint: String = CompanionAppGroup.usesAppGroup ? "App Group ok" : "Fallback local (Personal Team)"
  @Published var isBusy = false
  @Published var chatText = ""
  @Published var apiBase: String = APIConfig.baseURL.absoluteString
  @Published var companionIdInput: String = CompanionSnapshotStore.savedCompanionId() ?? ""

  func bootstrap() async {
    apply(snapshot: CompanionSnapshotStore.load() ?? .demo, reaction: nil)
    await refresh()
  }

  func saveAPIBase() {
    APIConfig.setBaseURL(apiBase.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  func saveCompanionId() {
    let id = companionIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
    CompanionSnapshotStore.saveCompanionId(id)
  }

  func pasteCompanionIdFromClipboard() {
    #if canImport(UIKit)
    if let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
       text.hasPrefix("cmp-") {
      companionIdInput = text
      saveCompanionId()
      reaction = "ID colado. Toque em Atualizar."
    } else {
      reaction = "Clipboard sem ID (precisa começar com cmp-)."
    }
    #endif
  }

  func refresh() async {
    isBusy = true
    defer { isBusy = false }
    do {
      saveAPIBase()
      saveCompanionId()
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

  /// Dispara a Island ao sair do app (background). One-shot: corre → dano → some.
  func startIslandOnLeave() {
    do {
      _ = try LiveActivityController.start(snapshot: snapshot, line: reaction)
    } catch {
      print("[island] \(error.localizedDescription)")
    }
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
    storageHint = CompanionAppGroup.usesAppGroup ? "App Group ok" : "Fallback local (Personal Team)"
    WidgetReloader.reload()
  }
}

struct ContentView: View {
  @StateObject private var model = CompanionViewModel()
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          petCard
          reactionCard
          actions
          chatRow
          islandHint
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
      .onChange(of: scenePhase) { phase in
        if phase == .background {
          model.startIslandOnLeave()
        }
      }
    }
  }

  private var petCard: some View {
    VStack(spacing: 12) {
      DinoAvatar(skin: model.snapshot.skin, size: 120)
      Text(model.snapshot.name)
        .font(.largeTitle.bold())
      Text("\(model.snapshot.moodEmoji) \(model.snapshot.moodText)")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      HStack(spacing: 16) {
        meter(title: "Energia", value: model.snapshot.energyPercent, color: .green)
        meter(title: "Afeto", value: model.snapshot.affectionPercent, color: .pink)
      }
      Text("\(model.status) · \(model.storageHint)")
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
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        TextField("Fala com o dino… (ex: qual a temperatura?)", text: $model.chatText)
          .textFieldStyle(.roundedBorder)
        Button("Enviar") {
          Task { await model.interact("CHAT") }
        }
        .disabled(model.isBusy || model.chatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      Text("Clima e chat usam a API no Mac (mesma Wi‑Fi).")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }

  private var islandHint: some View {
    Text("Ao sair do app, o dino aparece na Dynamic Island: corre, toma dano na borda e some.")
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private var settings: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("API base (no iPhone use o IP do Mac)").font(.caption).foregroundStyle(.secondary)
      TextField("http://192.168.x.x:3333", text: $model.apiBase)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .textFieldStyle(.roundedBorder)
        .onSubmit { model.saveAPIBase() }

      Text("Companion ID (do desktop / data/companions.json)").font(.caption).foregroundStyle(.secondary)
      HStack {
        TextField("cmp-…", text: $model.companionIdInput)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .textFieldStyle(.roundedBorder)
        Button("Colar") { model.pasteCompanionIdFromClipboard() }
          .buttonStyle(.bordered)
      }
      .onSubmit { model.saveCompanionId() }

      Text("Após mudar IP/ID, toque em Atualizar. Widgets leem o snapshot salvo pelo app.")
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
