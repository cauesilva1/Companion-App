import SwiftUI

struct QuizView: View {
  /// Chamado após nascimento local (e cloud, se disponível) com o snapshot a carregar na ContentView.
  var onFinished: (CompanionSnapshot, CompanionQuiz.Draft) -> Void

  @State private var step = 0
  @State private var choices: [Int] = []
  @State private var draft: CompanionQuiz.Draft?
  @State private var nameInput = ""
  @State private var isSaving = false
  @State private var errorMessage: String?
  @FocusState private var nameFocused: Bool

  private var questions: [CompanionQuiz.Question] { CompanionQuiz.questions }
  private var isReveal: Bool { step >= questions.count }

  var body: some View {
    ZStack {
      SkyBackground(artOpacity: 0.22)
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text("Quem vai nascer?")
            .font(.caption.weight(.bold))
            .foregroundStyle(CompanionTheme.subtitle)
          progressRow
          if isReveal, let draft {
            reveal(draft)
          } else if step < questions.count {
            questionBlock(questions[step])
          }
        }
        .padding(20)
        .background(
          RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white)
            .shadow(color: .black.opacity(0.14), radius: 16, y: 6)
        )
        .padding(18)
        .padding(.top, 24)
      }
    }
    .preferredColorScheme(.light)
    .interactiveDismissDisabled(isSaving)
  }

  private var progressRow: some View {
    HStack(spacing: 8) {
      ForEach(0..<questions.count, id: \.self) { i in
        Circle()
          .fill(i < step ? CompanionTheme.play : (i == step ? CompanionTheme.feed : Color.black.opacity(0.12)))
          .frame(width: 10, height: 10)
      }
      Spacer()
      Text(isReveal ? "Pronto" : "\(step + 1) / \(questions.count)")
        .font(.caption.weight(.semibold))
        .foregroundStyle(CompanionTheme.subtitle)
    }
  }

  private func questionBlock(_ q: CompanionQuiz.Question) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(q.prompt)
        .font(.title3.weight(.bold))
        .foregroundStyle(CompanionTheme.title)
        .fixedSize(horizontal: false, vertical: true)
      ForEach(Array(q.options.enumerated()), id: \.offset) { idx, opt in
        Button {
          select(idx)
        } label: {
          Text(opt.label)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(CompanionTheme.title)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
              RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.93, green: 0.96, blue: 1.0))
            )
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
      }
    }
  }

  private func reveal(_ draft: CompanionQuiz.Draft) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Esse é o seu dino")
        .font(.title3.weight(.bold))
        .foregroundStyle(CompanionTheme.title)
      HStack(spacing: 14) {
        DinoStaticFrame(skin: draft.skin, size: 72)
        Text(draft.blurb)
          .font(.subheadline)
          .foregroundStyle(CompanionTheme.subtitle)
          .fixedSize(horizontal: false, vertical: true)
      }
      Text("Nome")
        .font(.caption.weight(.semibold))
        .foregroundStyle(CompanionTheme.subtitle)
      TextField("Nome do companion", text: $nameInput)
        .textInputAutocapitalization(.words)
        .disableAutocorrection(true)
        .focused($nameFocused)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.06)))
        .foregroundStyle(CompanionTheme.title)
        .onAppear {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            nameFocused = true
          }
        }

      if let errorMessage {
        Text(errorMessage)
          .font(.caption.weight(.medium))
          .foregroundStyle(Color.red.opacity(0.9))
          .fixedSize(horizontal: false, vertical: true)
      }

      Button {
        nameFocused = false
        Task { await finalizeBirth(draft) }
      } label: {
        HStack {
          if isSaving {
            ProgressView()
              .tint(.white)
          }
          Text(isSaving ? "Nascendo…" : "Nascer")
            .font(.headline.weight(.bold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(CompanionTheme.play.opacity(isSaving ? 0.7 : 1)))
      }
      .buttonStyle(.plain)
      .disabled(isSaving)
    }
  }

  private func select(_ idx: Int) {
    if choices.count == step {
      choices.append(idx)
    } else if choices.count > step {
      choices[step] = idx
    } else {
      while choices.count < step { choices.append(0) }
      choices.append(idx)
    }
    let next = step + 1
    if next >= questions.count {
      let d = CompanionQuiz.derive(choices: choices)
      draft = d
      nameInput = d.name
      step = next
    } else {
      step = next
    }
  }

  @MainActor
  private func finalizeBirth(_ draft: CompanionQuiz.Draft) async {
    guard !isSaving else { return }
    isSaving = true
    errorMessage = nil

    let name = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
    let finalName = name.isEmpty ? draft.name : name
    let traits = CompanionQuiz.buildTraits(choices: choices, draft: draft)
    // Guarda no aparelho para o login/sync mandar tudo à cloud depois.
    CompanionQuiz.saveTraits(traits)

    // Sempre permite nascer: tenta cloud; se sessão falhar, nasce local e segue.
    if SupabaseConfig.isConfigured {
      let session = await SupabaseClient.shared.ensurePersistentSession()
      if session != nil {
        do {
          let created = try await SupabaseClient.shared.createCompanionFromQuiz(
            name: finalName,
            draft: draft,
            traits: traits
          )
          onFinished(created, draft)
          return
        } catch {
          // Auth/rede: não prende o usuário na tela do quiz.
          let local = await CompanionEngine.shared.birthFromQuiz(draft: draft, name: finalName)
          SyncQueue.enqueuePushState(local)
          onFinished(local, draft)
          return
        }
      }
      // Sem sessão (Anonymous off / rede): nasce local mesmo assim.
      let local = await CompanionEngine.shared.birthFromQuiz(draft: draft, name: finalName)
      SyncQueue.enqueuePushState(local)
      onFinished(local, draft)
      return
    }

    let local = await CompanionEngine.shared.birthFromQuiz(draft: draft, name: finalName)
    onFinished(local, draft)
  }
}
