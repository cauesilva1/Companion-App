import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
                  ? "Crie sua conta para guardar o companion na nuvem (iPhone e Mac)."
                  : "Entre com o email da conta. Se já tiver companion, ele volta do jeito que estava."
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
                Self.dismissKeyboard()
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
      .scrollDismissesKeyboard(.interactively)
    }
    .preferredColorScheme(.light)
    .navigationTitle("Conta")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("OK") { Self.dismissKeyboard() }
      }
    }
    .onAppear {
      if startInRegister { isRegister = true }
    }
  }

  private static func dismissKeyboard() {
    #if canImport(UIKit)
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder),
      to: nil,
      from: nil,
      for: nil
    )
    #endif
  }

  private func submit() async {
    busy = true
    errorText = nil
    defer { busy = false }
    let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let registerMode = isRegister
    let passwordCopy = password
    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { @MainActor in
          if registerMode {
            try await model.register(email: trimmedEmail, password: passwordCopy)
          } else {
            try await model.login(email: trimmedEmail, password: passwordCopy)
          }
        }
        group.addTask {
          try await Task.sleep(nanoseconds: 25_000_000_000)
          throw TimeoutError()
        }
        try await group.next()
        group.cancelAll()
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
