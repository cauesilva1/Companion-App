import SwiftUI

struct LoginView: View {
  @ObservedObject var model: CompanionViewModel
  var startInRegister: Bool = false
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
              Text(
                isRegister
                  ? "Assim \(model.snapshot.name) fica salvo online — não só neste iPhone."
                  : "Mesmo email no iPhone e no Mac → mesmo companion."
              )
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
    .onAppear {
      if startInRegister { isRegister = true }
    }
  }

  private func submit() async {
    busy = true
    errorText = nil
    defer { busy = false }
    let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    do {
      try await withTimeout(seconds: 25) {
        if self.isRegister {
          try await self.model.register(email: trimmedEmail, password: self.password)
        } else {
          try await self.model.login(email: trimmedEmail, password: self.password)
        }
      }
      model.preferRegisterOnLogin = false
    } catch is TimeoutError {
      errorText = "Demorou demais. Confira a rede e tente de novo."
    } catch {
      errorText = error.localizedDescription
    }
  }
}

private struct TimeoutError: Error {}

private func withTimeout<T: Sendable>(
  seconds: Double,
  operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask { try await operation() }
    group.addTask {
      try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      throw TimeoutError()
    }
    guard let result = try await group.next() else { throw TimeoutError() }
    group.cancelAll()
    return result
  }
}
