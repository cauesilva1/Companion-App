import SwiftUI

struct QuizView: View {
  var onFinished: (CompanionQuiz.Draft, String) -> Void

  @State private var step = 0
  @State private var choices: [Int] = []
  @State private var draft: CompanionQuiz.Draft?
  @State private var nameInput = ""

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
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.06)))
        .foregroundStyle(CompanionTheme.title)
      Button {
        let name = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        onFinished(draft, name.isEmpty ? draft.name : name)
      } label: {
        Text("Nascer")
          .font(.headline.weight(.bold))
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .background(RoundedRectangle(cornerRadius: 16).fill(CompanionTheme.play))
      }
      .buttonStyle(.plain)
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
}
