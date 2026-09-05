import SwiftUI

struct LoginView: View {
  @ObservedObject var model: CompanionViewModel
  @State private var email = ""
  @State private var password = ""
  @State private var isRegister = false
  @State private var busy = false
  @State private var errorText: String?

  var body: some View {
    ZStack {
      SkyBackground(artOpacity: 0.25)
      ScrollView {
        VStack(spacing: 18) {
          CompanionCard {
            VStack(alignment: .leading, spacing: 10) {
              Text(isRegister ? "Criar conta" : "Entrar")
                .font(.title2.bold())
                .foregroundStyle(CompanionTheme.title)
              Text("Mesmo email no iPhone e no Mac → mesmo companion.")
                .font(.subheadline)
                .foregroundStyle(CompanionTheme.subtitle)

              if !SupabaseConfig.isConfigured {
                Text("Cloud ainda não embutido neste build. No Mac: coloque SUPABASE_URL + SUPABASE_ANON_KEY no .env e rode node scripts/sync-supabase-config.mjs")
                  .font(.caption)
                  .foregroundStyle(.orange)
              }

              TextField("email@exemplo.com", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.06)))
              SecureField("senha (mín. 6)", text: $password)
                .textContentType(isRegister ? .newPassword : .password)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.06)))

              if let errorText {
                Text(errorText)
                  .font(.caption)
                  .foregroundStyle(.red)
              }
              Button {
                Task { await submit() }
              } label: {
                Text(busy ? "…" : (isRegister ? "Criar conta" : "Entrar"))
                  .font(.subheadline.weight(.bold))
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 14)
                  .foregroundStyle(.white)
                  .background(RoundedRectangle(cornerRadius: 14).fill(CompanionTheme.play))
              }
              .buttonStyle(.plain)
              .disabled(busy || email.isEmpty || password.count < 6 || !SupabaseConfig.isConfigured)

              Button(isRegister ? "Já tenho conta" : "Criar conta") {
                isRegister.toggle()
                errorText = nil
              }
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(CompanionTheme.poke)
            }
          }
        }
        .padding(18)
      }
    }
    .preferredColorScheme(.light)
    .navigationTitle("Conta")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func submit() async {
    busy = true
    defer { busy = false }
    errorText = nil
    do {
      if isRegister {
        try await model.register(email: email, password: password)
      } else {
        try await model.login(email: email, password: password)
      }
    } catch {
      errorText = error.localizedDescription
    }
  }
}
