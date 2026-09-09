import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct SettingsView: View {
  @ObservedObject var model: CompanionViewModel
  @ObservedObject private var spotify = SpotifyService.shared
  @ObservedObject private var nowPlaying = NowPlayingService.shared

  var body: some View {
    ZStack {
      SkyBackground(artOpacity: 0.22)
      ScrollView {
        VStack(spacing: 16) {
          header
          accountCard
          prefsCard
          keysCard
          advancedCard
          statusCard
        }
        .padding(18)
        .padding(.bottom, 24)
      }
    }
    .preferredColorScheme(.light)
    .navigationTitle("Configuração")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbarBackground(Color.white.opacity(0.92), for: .navigationBar)
    .toolbarColorScheme(.light, for: .navigationBar)
    .scrollDismissesKeyboard(.interactively)
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("OK") { dismissKeyboard() }
      }
    }
  }

  private var header: some View {
    CompanionCard {
      NavigationLink {
        ProfileView(model: model)
      } label: {
        HStack(spacing: 12) {
          DinoStaticFrame(skin: model.snapshot.skin, size: 48)
          VStack(alignment: .leading, spacing: 4) {
            Text(model.snapshot.name)
              .font(.title3.bold())
              .foregroundStyle(CompanionTheme.title)
            if let title = model.snapshot.activeTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty {
              Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CompanionTheme.play)
            } else {
              Text(LocalVoice.archetypeLabel(model.snapshot.archetype))
                .font(.caption.weight(.semibold))
                .foregroundStyle(CompanionTheme.play)
            }
            Text("Ver perfil e badges")
              .font(.caption)
              .foregroundStyle(CompanionTheme.subtitle)
          }
          Spacer()
          Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(CompanionTheme.subtitle)
        }
      }
      .buttonStyle(.plain)
    }
  }

  private var accountCard: some View {
    CompanionCard {
      VStack(alignment: .leading, spacing: 12) {
        Text("Conta")
          .font(.headline)
          .foregroundStyle(CompanionTheme.title)
        Text(SupabaseConfig.isConfigured
          ? "Entre com email e senha. O companion fica vinculado à conta na nuvem."
          : "Cloud não configurado neste build.")
          .font(.caption)
          .foregroundStyle(CompanionTheme.subtitle)
        if model.hasRealAccount {
          Text(model.accountEmail)
            .font(.subheadline)
            .foregroundStyle(CompanionTheme.subtitle)
          Button("Sair da conta") {
            dismissKeyboard()
            model.logout()
          }
          .foregroundStyle(.red)
          Text("Sair limpa só este iPhone. O companion na cloud permanece na conta.")
            .font(.caption2)
            .foregroundStyle(CompanionTheme.subtitle)
        } else {
          NavigationLink("Entrar / criar conta") {
            LoginView(model: model)
          }
          .font(.subheadline.weight(.bold))
        }
      }
    }
  }

  private var prefsCard: some View {
    CompanionCard {
      VStack(alignment: .leading, spacing: 12) {
        Text("Preferências")
          .font(.headline)
          .foregroundStyle(CompanionTheme.title)
        Toggle("Som", isOn: Binding(
          get: { !model.soundMuted },
          set: { model.setSoundMuted(!$0) }
        ))
        .foregroundStyle(CompanionTheme.title)
        .tint(CompanionTheme.play)
        Toggle("Detectar música (Spotify)", isOn: Binding(
          get: { model.nowPlayingEnabled },
          set: { model.setNowPlaying($0) }
        ))
        .foregroundStyle(CompanionTheme.title)
        .tint(CompanionTheme.play)
        Toggle("Notificar troca de faixa", isOn: Binding(
          get: { model.musicNotifEnabled },
          set: { model.setMusicNotif($0) }
        ))
        .foregroundStyle(CompanionTheme.title)
        .tint(CompanionTheme.play)

        if spotify.isConnected {
          Text("Spotify conectado · \(nowPlaying.source)")
            .font(.caption)
            .foregroundStyle(CompanionTheme.play)
          Button("Desconectar Spotify") {
            SpotifyService.shared.disconnect()
            NowPlayingService.shared.refresh()
            model.reaction = "Spotify desconectado."
          }
          .foregroundStyle(.red)
        } else if spotify.hasClientId {
          Button("Conectar Spotify") {
            Task { await model.connectSpotify() }
          }
          .font(.subheadline.weight(.bold))
        } else {
          Text("Spotify ainda não embutido neste build (SPOTIFY_CLIENT_ID no .env + sync).")
            .font(.caption2)
            .foregroundStyle(CompanionTheme.subtitle)
        }
        Text("Login com a conta Spotify. No carro: o app só vê a faixa se o Spotify estiver conectado aqui e tocando na conta (API). Apple Music / rádio do carro não aparecem.")
          .font(.caption2)
          .foregroundStyle(CompanionTheme.subtitle)

        Text("Casa / Sofá")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(CompanionTheme.title)
          .padding(.top, 4)
        Text("SSID da casa: \(LifeModeStore.homeWifiSsid ?? "não definido")")
          .font(.caption)
          .foregroundStyle(CompanionTheme.subtitle)
        if !ContextTelemetryService.shared.locationAuthorized {
          Text("Localização necessária para ler o nome da rede Wi‑Fi.")
            .font(.caption2)
            .foregroundStyle(.orange)
        }
        Button("Permitir localização / marcar Wi‑Fi como casa") {
          Task {
            let ok = await ContextTelemetryService.shared.ensureLocationForWifiSsid()
            if !ok {
              model.reaction = "Ative Localização → Durante o uso do app em Ajustes do iPhone."
              return
            }
            if let ssid = await ContextTelemetryService.shared.captureCurrentSsidAsHome() {
              model.reaction = "Rede de casa: \(ssid)"
            } else {
              model.reaction =
                "Localização ok. Se o nome da rede não aparecer, digite o SSID abaixo (Access Wi‑Fi Info exige conta Apple Developer paga)."
            }
          }
        }
        .font(.subheadline.weight(.semibold))
        TextField("SSID da casa (ex: MinhaRede)", text: Binding(
          get: { LifeModeStore.homeWifiSsid ?? "" },
          set: { LifeModeStore.homeWifiSsid = $0.isEmpty ? nil : $0 }
        ))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.done)
        .onSubmit { dismissKeyboard() }
        TextField("Gamertag Xbox (opcional)", text: Binding(
          get: { LifeModeStore.xboxGamertag ?? "" },
          set: { LifeModeStore.xboxGamertag = $0.isEmpty ? nil : $0 }
        ))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.done)
        .onSubmit { dismissKeyboard() }
        Button("Salvar contexto na cloud") {
          Task {
            _ = await ContextTelemetryService.shared.ensureLocationForWifiSsid()
            await ContextTelemetryService.shared.ingestNow()
            model.reaction = "Contexto enviado · \(ContextTelemetryService.shared.lastLifeMode.labelPT)"
          }
        }
        .font(.subheadline.weight(.bold))
        Text("Modo agora: \(CompanionLifeMode.parse(model.snapshot.lifeMode).labelPT)")
          .font(.caption2)
          .foregroundStyle(CompanionTheme.play)
          .onAppear {
            Task { _ = await ContextTelemetryService.shared.ensureLocationForWifiSsid() }
          }

        Toggle("Pegadinhas", isOn: Binding(
          get: { model.pranksEnabled },
          set: { model.setPranks($0) }
        ))
        .foregroundStyle(CompanionTheme.title)
        .tint(CompanionTheme.play)
        Toggle("Avisar energia baixa", isOn: Binding(
          get: { model.lowEnergyNotifEnabled },
          set: { on in Task { await model.setLowEnergyNotif(on) } }
        ))
        .foregroundStyle(CompanionTheme.title)
        .tint(CompanionTheme.play)
        Toggle("Avisar saudade", isOn: Binding(
          get: { model.missYouNotifEnabled },
          set: { on in Task { await model.setMissYouNotif(on) } }
        ))
        .foregroundStyle(CompanionTheme.title)
        .tint(CompanionTheme.play)
      }
    }
  }

  private var keysCard: some View {
    CompanionCard {
      VStack(alignment: .leading, spacing: 12) {
        Text("Chaves LLM")
          .font(.headline)
          .foregroundStyle(CompanionTheme.title)
        SecureField("NVIDIA API Key", text: $model.nvidiaKey)
          .foregroundStyle(CompanionTheme.title)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .padding(12)
          .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.06)))
        SecureField("OpenRouter API Key", text: $model.openrouterKey)
          .foregroundStyle(CompanionTheme.title)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .padding(12)
          .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.06)))
        Button {
          model.saveKeys()
        } label: {
          Text("Salvar chaves")
            .font(.subheadline.weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 14).fill(CompanionTheme.play))
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var advancedCard: some View {
    CompanionCard {
      VStack(alignment: .leading, spacing: 12) {
        Text("Avançado")
          .font(.headline)
          .foregroundStyle(CompanionTheme.title)
        Toggle("Usar API do Mac (LAN)", isOn: Binding(
          get: { model.useLanAPI },
          set: { model.setLanMode($0); Task { await model.refresh() } }
        ))
        .foregroundStyle(CompanionTheme.title)
        .tint(CompanionTheme.play)
        if model.useLanAPI {
          TextField("http://192.168.x.x:3333", text: $model.apiBase)
            .foregroundStyle(CompanionTheme.title)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.06)))
            .onSubmit { model.saveAPIBase() }
          HStack {
            TextField("ID do companion", text: $model.companionIdInput)
              .foregroundStyle(CompanionTheme.title)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .padding(12)
              .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.06)))
            Button("Colar") { model.pasteCompanionIdFromClipboard() }
              .buttonStyle(.bordered)
          }
          .onSubmit { model.saveCompanionId() }
        }
      }
    }
  }

  private var statusCard: some View {
    CompanionCard {
      VStack(alignment: .leading, spacing: 10) {
        Text("Status")
          .font(.headline)
          .foregroundStyle(CompanionTheme.title)
        row("Modo", model.useLanAPI ? "API Mac" : (model.hasRealAccount ? "Supabase" : "Standalone"))
        row("Conta", model.hasRealAccount ? model.accountEmail : "—")
        row("Supabase", SupabaseConfig.isConfigured ? "Configurado" : "Falta URL/key")
        row("LLM", KeychainStore.hasAnyLLMKey ? "Com chave" : "Frases locais")
        row("Música", model.nowPlayingEnabled ? "On" : "Off")
        row("Pegadinhas", model.pranksEnabled ? "On" : "Off")
        row("API", model.status)
      }
    }
  }

  private func row(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title).foregroundStyle(CompanionTheme.subtitle)
      Spacer()
      Text(value).fontWeight(.semibold).foregroundStyle(CompanionTheme.title)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .font(.subheadline)
  }

  private func dismissKeyboard() {
    #if canImport(UIKit)
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder),
      to: nil,
      from: nil,
      for: nil
    )
    #endif
  }
}
