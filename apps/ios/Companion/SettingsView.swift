import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct SettingsView: View {
  @ObservedObject var model: CompanionViewModel

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
  }

  private var header: some View {
    CompanionCard {
      HStack(spacing: 12) {
        DinoStaticFrame(skin: model.snapshot.skin, size: 48)
        VStack(alignment: .leading, spacing: 4) {
          Text(model.snapshot.name)
            .font(.title3.bold())
            .foregroundStyle(CompanionTheme.title)
          Text(LocalVoice.archetypeLabel(model.snapshot.archetype))
            .font(.caption.weight(.semibold))
            .foregroundStyle(CompanionTheme.play)
          Text("Ajustes do companion")
            .font(.caption)
            .foregroundStyle(CompanionTheme.subtitle)
        }
        Spacer()
      }
    }
  }

  private var accountCard: some View {
    CompanionCard {
      VStack(alignment: .leading, spacing: 12) {
        Text("Conta")
          .font(.headline)
          .foregroundStyle(CompanionTheme.title)
        Text(SupabaseConfig.isConfigured ? "Cloud pronto (embutido no app)." : "Cloud não configurado neste build.")
          .font(.caption)
          .foregroundStyle(CompanionTheme.subtitle)
        if model.isLoggedIn {
          Text(model.accountEmail)
            .font(.subheadline)
            .foregroundStyle(CompanionTheme.subtitle)
          Button("Sair da conta") { model.logout() }
            .foregroundStyle(.red)
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
        Toggle("Mostrar música (Now Playing)", isOn: Binding(
          get: { model.nowPlayingEnabled },
          set: { model.setNowPlaying($0) }
        ))
        .foregroundStyle(CompanionTheme.title)
        .tint(CompanionTheme.play)
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
        row("Modo", model.useLanAPI ? "API Mac" : (model.isLoggedIn ? "Supabase" : "Standalone"))
        row("Conta", model.isLoggedIn ? model.accountEmail : "—")
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
}
